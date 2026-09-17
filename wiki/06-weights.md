# 6 — Weights

The plugin downloads. Containers only read. Nothing inside a container ever writes weights.

## Where weights go

The recipe's mounts decide, and `weights_dest_compute` reads exactly that:

| Mount present | `kind` | base | Download lands at |
|---|---|---|---|
| `${MODEL_ROOT}/<dir>` (first match wins) | `dir` | `<MODEL_ROOT>/<dir>` | `<base>/<weights.subdir>` |
| none | `hf` | `$HF_HOME` | the shared Hugging Face cache, hub layout |

`weights.subdir` exists because TabbyAPI loads `<mount>/<model_name>`: files at the mount root would
make every TabbyAPI recipe unstartable. The result is cached per recipe id (`WDEST`), because one
snapshot asks several times per recipe.

## The completion marker — `$STATE/weights/<recipe-id>.json`

```json
{ "repository": "org/repo", "revision": "<40-64 hex>", "completedAt": "…",
  "kind": "dir", "path": "/home/u/.cache/omarchy/local-ai/models/test/Test-Model" }
```

**Presence is the marker AND the files.** A marker outlives a deleted directory (a cache wipe, a
hand-made cleanup), and an engine started over an empty read-only mount tries to download into it,
crashes, and restarts forever — the bug that made this rule explicit.

### `weights_marked`

True when any marker satisfies `repository == .model.repository` and `revision == .model.revision`,
where:

- the recipe's **own** marker matches on repository and revision alone;
- any **other** recipe's marker must also carry the same `kind` and `path` — that is how a
  tensor-parallel variant reuses a downloaded model's weights at the same place, with no second
  download.

A revision bump invalidates every marker and re-downloads.

### `weights_files_ok`

| Kind | Check |
|---|---|
| `hf` | `<HF_HOME>/hub/models--<repo, / → -->/snapshots/<revision>` has at least one non-empty file within 3 levels, ignoring `.cache` |
| `dir`, `servedName` ends `.gguf` | `<base>/<basename of servedName>` exists and is non-empty |
| `dir`, otherwise | at least one non-empty file within 3 levels of `<base>`, ignoring `.cache` |

`.cache` is pruned because that is where Hugging Face keeps partials and metadata; downloads land
whole, and a partial is never mistaken for a complete one.

`weights_present = marked && files_ok`. `weights_partial_bytes` reports what is on disk for an
incomplete recipe (for a hub recipe, that repository's own cache directory) — the card's *resume*.

## Downloading

### Host `hf` (preferred) — `download_host`

Used when `hf` is on `PATH` (or `$HOME/.local/bin/hf`) and `OMARCHY_AI_NO_HOST_HF` is unset.

```
dir kind:  hf download <repo> --revision <rev> --local-dir <base>  [--include <file> --include *mmproj*]
hub kind:  HF_HOME=<base> hf download <repo> --revision <rev>      [--include <file> --include *mmproj*]
```

The `--include` pair appears only for a single-file GGUF recipe: the repository may hold a dozen
quantisations and only the served file (plus an `mmproj` projector for vision GGUFs) is needed.
Progress is the directory's size against `WEXP = floor(sizeGb × 2^30)`, sampled every `POLL` seconds,
with rate and ETA from the previous sample — the card's `12 / 18 GB · about 6m41s left`.

### The recipe's own image — `download_run`

Inside a start phase, when the host has no `hf`. The engine image always carries `huggingface_hub`,
because the engine loads from the Hub:

```
docker run --rm --user <RUN_AS> --label io.omarchy.local-ai.download=1 --network bridge \
  --env HF_HOME=/tmp/hf (dir) | /hf (hub)  --env HOME=/tmp  [--env HF_TOKEN] \
  --env HF_REPO=… --env HF_REV=… [--env HF_PATTERN=…] \
  --volume <base>:/weights (dir) | /hf (hub) \
  --entrypoint python3 <engine image> -c "from huggingface_hub import snapshot_download as d; …"
```

`HF_HOME` must be writable for the hub cache and xet chunks, hence `/tmp/hf` in dir mode. Failures go
through `docker_reason`. The label makes this container the thing `unload` can kill.

### Free space

`weights_plan` runs `df -Pk <base>` and refuses when `free < WEXP − bytes_already_there`, as
`need <n> GB free under <base>`. For a hub recipe the measurement is that repository's own cache
directory, not the whole shared HF cache.

### Stopping a download

`unload` during a `download` calls `cancel_download`: behind a password prompt (no `docker_direct`,
no host `hf`) it refuses with *the download runs behind the password prompt and cannot be stopped from
here*. Otherwise it writes `$STATE/cancel`, TERMs the worker's process group, waits up to 10 s, KILLs,
removes labelled downloader containers, clears the op, logs *download stopped; partial weights kept*.
The `cancel` marker tells the worker's `EXIT` trap this was requested, not a crash.

Partials stay on disk, unmarked. The next `load` resumes — the card shows *resume + run*.

## Adopting weights you already have — `weights_find`

Before any download, the plugin looks for a **verified** copy on the machine.

### What is needed

`weights_needed` builds the expected file list from the Hub's tree of the **pinned revision**:

```
GET https://huggingface.co/api/models/<repo>/tree/<rev>?recursive=1   (30 s, 4 MiB cap, HF_TOKEN optional)
→ <path>\t<size>\t<sha256 or ->\t<git blob oid or ->    cached in $STATE/trees/<repo>@<rev>.tsv
```

- a GGUF recipe with `model.sha256` needs no network: the single expected line is synthesised;
- a GGUF recipe without it needs exactly that one file;
- anything else needs every file except `README`, `LICENSE`, `NOTICE`, `.gitattributes` and
  `*.md|png|jpg|jpeg|gif|svg|webp`.

Offline with no cached tree → `cannot list <repo>@<rev> on the Hub (offline?); nothing adopted`, and
the download proceeds.

### Where it looks

`$HOME/models`, `$MODEL_ROOT`, `$HF_HOME/hub/models--<repo>/snapshots`, `$HOME/.cache/llama.cpp`, then
each colon-separated entry of `OMARCHY_AI_WEIGHTS_PATHS`. Under each root it searches up to 5 levels
deep for a file named like the recipe's **largest** needed file — that name is the signature of a
complete copy — collecting up to 20 candidate directories, skipping the destination itself and the HF
cache's `blobs/` store.

### How it verifies

1. **Sizes first** (cheap; a wrong quant fails here): `found <cand> but <path> is missing or its size
   differs from the pinned file; skipped`.
2. **Then every checksum**: SHA-256 for LFS files, git blob SHA-1 (`sha1("blob <size>\0" + contents)`)
   for the rest: `found <cand> but <path>'s checksum differs from the pinned file; skipped`.
3. The first candidate that passes every file is placed.

### How it places

`place_file` tries `cp --reflink=always` (free on btrfs), then `ln` (hard link), then a plain copy,
and finishes with `chmod go+r` because the engine container runs as another uid.

| Kind | Result |
|---|---|
| `dir` | every file placed at `<base>/<path>` |
| `hf` | `<HF_HOME>/hub/models--<repo>/blobs/<etag>` (etag = SHA-256 for LFS files, git blob id otherwise) plus `snapshots/<rev>/<path>` symlinks to `../../blobs/<etag>`, with one `../` per path level |

Success shows `using the copy at <path>` on the card and logs
`adopted <dir> as <dest> (<n> files, verified against <repo>@<rev12>)`, then writes the marker. A
placement failure logs `could not place the copy from <cand>; downloading instead` and the normal
download runs.

Nothing unverified is ever served: a same-named older quant, or one edited `config.json`, is refused
and the pinned files are fetched.