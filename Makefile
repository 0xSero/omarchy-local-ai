# sync:  take the registry's published recipe export (it stamps the registry commit)
# native: write Omarchy's native view from this plugin's own UI (OMARCHY=<checkout>)
# check: tests plus a recipes.json sanity check
REGISTRY ?= ../local-ai-registry

.PHONY: sync sync-check native native-check check test bundle

BUNDLE = dist/omarchy-local-ai-$(shell jq -r .version manifest.json).tar.gz
RUNTIME = manifest.json recipes.json LICENSE bin/omarchy-local-ai $(wildcard lib/*.sh lib/*.py) $(wildcard ui/*.qml) ui/ui.js $(wildcard integrations/*.py integrations/*.patch integrations/*.lua integrations/*.qml integrations/*.html)

bundle:
	mkdir -p dist
	COPYFILE_DISABLE=1 tar -czf $(BUNDLE) $(RUNTIME)

# The registry authors recipes.json and publishes it at plugin/recipes.json, where its own CI keeps it
# current. This repo only vendors that file: `make sync` takes it verbatim and `make sync-check` fails when
# the vendored copy has fallen behind it. No recipe is ever written here.
REGISTRY_EXPORT = $(REGISTRY)/plugin/recipes.json

sync:
	@test -f "$(REGISTRY_EXPORT)" || { echo "sync: no $(REGISTRY_EXPORT) - set REGISTRY=<registry checkout>" >&2; exit 2; }
	cp "$(REGISTRY_EXPORT)" recipes.json
	@jq -r '"recipes.json: \(.hardware|length) hardware ids from registry \(.registryCommit[:12]), \([.hardware[] | (.recipe.id), (.recipes[]?.id)] | length) recipes"' recipes.json

sync-check:
	@test -f "$(REGISTRY_EXPORT)" || { echo "sync-check: no $(REGISTRY_EXPORT) - set REGISTRY=<registry checkout>" >&2; exit 2; }
	@cmp -s "$(REGISTRY_EXPORT)" recipes.json \
	  && echo "recipes.json: current with the registry ($(REGISTRY))" \
	  || { echo "recipes.json is behind $(REGISTRY_EXPORT); run make sync" >&2; exit 1; }

native:
	@test -n "$(OMARCHY)" || { echo "native: set OMARCHY=<path to an Omarchy checkout>" >&2; exit 2; }
	python3 scripts/export_native_view.py --omarchy $(OMARCHY)

native-check:
	@test -n "$(OMARCHY)" || { echo "native-check: set OMARCHY=<path to an Omarchy checkout>" >&2; exit 2; }
	python3 scripts/export_native_view.py --omarchy $(OMARCHY) --check

test:
	bash test/bundle
	bash test/native

check: test
	@jq -e '.schemaVersion=="omarchy-local-ai/recipes/1" and (.registryCommit|test("^[0-9a-f]{40}$$")) and (.gateway.image|test("@sha256:[0-9a-f]{64}$$")) and (.hardware|length>0)' recipes.json >/dev/null \
	  && echo "recipes.json: ok" || { echo "recipes.json: missing schema, registry commit, or gateway image" >&2; exit 1; }
	@if [ -f "$(REGISTRY_EXPORT)" ]; then $(MAKE) --no-print-directory sync-check; \
	 else echo "recipes.json: registry not checked out at $(REGISTRY); the currency check was skipped"; fi
