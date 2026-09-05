#!/usr/bin/env python3
"""rented.py: run the plugin's own Start on rented GPUs, one card per hardware id.

    python3 test/rented.py <hardware-id>... [--provider vast|runpod] [--commit <sha>]
        [--registry ~/local-registry/local-ai-registry] [--gateway-commit main] [--disk 60]
        [--timeout 3600] [--keep] [--dry-run] [--parallel 1]
    python3 test/rented.py --list        # hardware ids in recipes.json with their engine and image host

Rented containers have no docker daemon. The recipe's own image is the container; the onstart
script materializes weights and assets at their mount targets (the registry's validate_rented.py
plan), then runs test/rented-inside.sh, which drives the shipped plugin CLI at --commit behind a
docker shim: the plugin's engine argv launches the engine as a process, its gateway argv starts
gateway.py, and the plugin's own acceptance chain decides. What this does not cover: docker itself,
bind-mount realization, and the previous-model rollback. Results land in test/rented-results/<hw>.json.

Provider notes are validate_rented.py's: RunPod community hosts cannot pull ghcr.io images
(tabbyapi recipes), so those go to Vast; sglang (Docker Hub) recipes run on either.
Credentials: ~/.config/vastai/vast_api_key, ~/.runpod/config.toml.
"""
import argparse, base64, concurrent.futures, importlib.util, json, os, re, shlex, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent
OUT = HERE / "rented-results"
REPO = "0xSero/omarchy-local-ai"
GATEWAY_REPO = "0xSero/local-ai-images"
RESULT_PORT = 12434


def log(msg):
    print(time.strftime("%H:%M:%S ") + msg, flush=True)


def load_validator(registry):
    path = Path(registry).expanduser() / "scripts" / "validate_rented.py"
    if not path.exists():
        raise SystemExit(f"no {path}: pass --registry")
    spec = importlib.util.spec_from_file_location("validate_rented", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def plugin_recipes():
    return json.loads((PLUGIN / "recipes.json").read_text())


def run_one(hw_id, args, vr):
    try:
        return run_one_inner(hw_id, args, vr)
    except SystemExit as e:   # a provider refusal (no offers, create failed) is this card's result, not the sweep's
        r = {"hardwareId": hw_id, "status": "no-offers", "detail": str(e)[:200]}
        OUT.mkdir(exist_ok=True); (OUT / f"{hw_id}.json").write_text(json.dumps(r, indent=1) + "\n")
        return r


def run_one_inner(hw_id, args, vr):
    recipes = plugin_recipes()
    entry = recipes["hardware"].get(hw_id)
    if not entry:
        return {"hardwareId": hw_id, "status": "skipped", "detail": "not in recipes.json"}
    recipe_id = entry["recipe"]["id"]
    path, recipe, contract = vr.load_recipe(recipe_id, revalidate=True)
    provider = vr.PROVIDERS[args.provider](args)
    if args.provider == "runpod" and contract["image"].startswith("ghcr.io/"):
        return {"hardwareId": hw_id, "status": "skipped", "detail": "runpod cannot pull ghcr.io images; use --provider vast"}

    class PluginSpec(vr.Spec):
        def onstart_script(self):
            # validate_rented's provisioning (weights and assets at their targets), then the harness instead of the engine
            base = super().onstart_script()
            parts = base.rsplit(" && exec ", 1)[0] if " && exec " in base else ""
            env = {
                "PLUGIN_URL": f"https://github.com/{REPO}/archive/{args.commit}.tar.gz",
                "PLUGIN_COMMIT": args.commit,
                "GATEWAY_URL": f"https://raw.githubusercontent.com/{GATEWAY_REPO}/{args.gateway_commit}/gateway/gateway.py",
                "HW_ID": hw_id, "RECIPE_ID": recipe_id, "RESULT_PORT": str(RESULT_PORT),
                "ENGINE_ENTRYPOINT": contract.get("entrypoint") or "", "ENGINE_TIMEOUT": str(args.timeout - 600),
                "MODEL_REPO": entry["recipe"]["model"]["repository"], "MODEL_REV": entry["recipe"]["model"]["revision"],
            }
            inside = base64.b64encode((HERE / "rented-inside.sh").read_bytes()).decode()
            exports = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items())
            run = f"mkdir -p /work && printf %s {inside} | base64 -d > /work/inside.sh && chmod +x /work/inside.sh && env {exports} bash /work/inside.sh"
            return f"{parts} && {run}" if parts else run

    spec = PluginSpec(recipe, contract, args)
    spec.port = RESULT_PORT   # the mapped port serves the result; the engine's own port stays inside
    # the harness must run even when nothing needs materializing (hub-cache recipes): the Vast path
    # only uses the onstart script when there are provisioning steps, so give it a harmless one, and
    # the RunPod path runs entrypoint+arguments directly, so make those the harness itself
    if not spec.provision:
        spec.provision = [("asset", "/work/.harness", "plugin harness\n")]
    if not spec.entrypoint:
        spec.entrypoint = "/bin/sh"
    if args.provider == "runpod":
        spec.entrypoint, spec.arguments = "/bin/sh", ["-c", spec.onstart_script()]
    spec.name = f"local-ai-plugin-{hw_id}"[:191]
    if args.dry_run:
        return {"hardwareId": hw_id, "recipeId": recipe_id, "status": "dry-run", "spec": spec.shown(), "onstart": spec.onstart_script()[:600]}

    exclude = set()
    handle = None
    started = time.monotonic()
    result = {"hardwareId": hw_id, "recipeId": recipe_id, "provider": args.provider, "status": "unknown"}
    try:
        for attempt in range(1, args.retries + 2):
            log(f"{hw_id}: attempt {attempt}: renting {provider.describe(spec)}, image {spec.image.split('@')[0]}")
            handle = provider.create(spec, exclude)
            handle["port"] = RESULT_PORT
            result.update({"instance": handle.get("id"), "gpu": handle.get("gpu"), "costPerHour": handle.get("cost"), "host": handle.get("host")})
            log(f"{hw_id}: {args.provider} {handle['id']} at {handle.get('cost')}/h on {handle.get('gpu')}")
            t0 = time.monotonic(); up = False; last = 0
            while True:
                endpoint = handle.get("endpoint")
                if endpoint:
                    try:
                        with urllib.request.urlopen(f"{endpoint}/result.json", timeout=10) as r:
                            body = json.loads(r.read().decode())
                            result.update(body); result["status"] = body.get("status", "unknown")
                            result["wallSeconds"] = int(time.monotonic() - t0)
                            return result
                    except Exception:
                        pass
                if time.monotonic() - t0 > args.timeout:
                    result.update({"status": "timeout", "detail": f"no result within {args.timeout}s"}); return result
                up_now, note = provider.poll(handle); up = up or up_now
                el = int(time.monotonic() - t0)
                # some hosts never expose the mapped port; the harness also prints its verdict to the
                # container log, so a running container that stays unreachable is read from there
                if up_now and el > args.reach_timeout and (el - (result.get("_lastLogPeek") or 0)) >= 60:
                    result["_lastLogPeek"] = el
                    verdict = provider_log_verdict(provider, handle)
                    if verdict:
                        result.update(verdict); result["wallSeconds"] = el; result["collectedFrom"] = "container log (port unreachable)"
                        result.pop("_lastLogPeek", None); return result
                if not up_now and el > args.start_timeout:   # current status, not latched: a host stuck on the pull stays "loading"
                    exclude.update({handle.get("offer"), handle.get("machine")})
                    log(f"{hw_id}: container not started after {el}s ({note}); trying another host")
                    provider.destroy(handle); handle = None
                    break
                if el - last >= 120:
                    log(f"{hw_id}: waiting ({el}s, {note}, container {'up' if up else 'not started'})")
                    last = el
                time.sleep(15)
            else:
                continue
        result.update({"status": "no-host", "detail": "no host started the container"}); return result
    finally:
        hours = (time.monotonic() - started) / 3600
        if handle:
            if args.keep:
                log(f"{hw_id}: keeping {handle['id']} ({handle.get('endpoint')})")
            else:
                try:
                    provider.destroy(handle); log(f"{hw_id}: destroyed {handle['id']}")
                except SystemExit as e:
                    log(f"{hw_id}: WARNING could not destroy {handle['id']}: {e}")
            if handle.get("cost"):
                result["approxCost"] = round(handle["cost"] * hours, 3)
                log(f"{hw_id}: approx cost {result['approxCost']:.2f} ({hours*60:.0f} min at {handle['cost']:.3f}/h)")
        OUT.mkdir(exist_ok=True)
        (OUT / f"{hw_id}.json").write_text(json.dumps(result, indent=1) + "\n")


def provider_log_verdict(provider, handle):
    """The harness's final 'result: <status> (<detail>)' line from the container log, or None."""
    if provider.name != "vast":
        return None
    try:
        out = subprocess.run(["vastai", "logs", str(handle["id"]), "--tail", "400"], capture_output=True, text=True, timeout=90).stdout
    except (subprocess.TimeoutExpired, OSError):
        return None
    m = None
    for line in out.splitlines():
        mm = re.search(r"result: (\S+) \((.*)\); serving on", line)
        if mm: m = mm
    if not m:
        return None
    verdict = {"status": m.group(1), "detail": m.group(2)}
    g = re.search(r"gpu: (NVIDIA[^\n]*)", out)
    if g: verdict["nvidiaSmi"] = g.group(1).strip()
    verdict["harnessLog"] = "\n".join(l for l in out.splitlines() if re.match(r"\d\d:\d\d:\d\d ", l))[-3000:]
    return verdict


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("hardware_ids", nargs="*")
    p.add_argument("--list", action="store_true")
    p.add_argument("--provider", default="vast", choices=["vast", "runpod"])
    p.add_argument("--commit", default=None, help="plugin commit to test (default: HEAD, must be pushed)")
    p.add_argument("--gateway-commit", default="main")
    p.add_argument("--registry", default="~/local-registry/local-ai-registry")
    p.add_argument("--gpu", default=None); p.add_argument("--cloud", default="COMMUNITY"); p.add_argument("--vast-min-inet", type=int, default=500)
    p.add_argument("--disk", type=int, default=60); p.add_argument("--timeout", type=int, default=3600)
    p.add_argument("--start-timeout", type=int, default=900); p.add_argument("--retries", type=int, default=1)
    p.add_argument("--reach-timeout", type=int, default=300, help="seconds a running container may stay unreachable before its logs are read for the result")
    p.add_argument("--keep", action="store_true"); p.add_argument("--dry-run", action="store_true")
    p.add_argument("--parallel", type=int, default=1)
    args = p.parse_args()
    recipes = plugin_recipes()
    if args.list:
        for hw, e in sorted(recipes["hardware"].items()):
            r = e["recipe"]; print(f"{hw:32} {r['engine']:10} {r['launch']['image'].split('/')[0]:14} {r['model']['name']}")
        return
    if not args.hardware_ids:
        p.error("hardware ids, or --list")
    if not args.commit:
        args.commit = subprocess.check_output(["git", "-C", str(PLUGIN), "rev-parse", "HEAD"], text=True).strip()
    vr = load_validator(args.registry)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as pool:
        for r in pool.map(lambda hw: run_one(hw, args, vr), args.hardware_ids):
            results.append(r)
            if args.dry_run:
                print(json.dumps(r, indent=1)); continue
            s = r.get("snapshot") or {}
            log(f"RESULT {r['hardwareId']}: {r['status']} | {r.get('detail','')} | gpu {r.get('gpu')} | {r.get('nvidiaSmi','')} | cost {r.get('approxCost','?')}")
    if not args.dry_run:
        print("\nhardware id                        status      detail")
        for r in results:
            print(f"{r['hardwareId']:34} {r['status']:11} {str(r.get('detail',''))[:90]}")
        sys.exit(0 if all(r["status"] == "ready" for r in results) else 1)


if __name__ == "__main__":
    main()
