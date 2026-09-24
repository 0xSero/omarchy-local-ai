# test:       every shell test (docker, curl, the GPU tools and pkexec are shimmed; node for Model.js)
# sync:       take every recipe of each card kind from the registry's published schema-2 export
#             (REGISTRY=<checkout>, at its origin/main), written one card kind per line
# sync-check: fail when the vendored copy has fallen behind that export
# check:      test, plus the recipes.json sanity and currency checks
# bundle:     the release archive: what an install contains, nothing else
REGISTRY ?= ../local-ai-registry
REGISTRY_REF ?= origin/main
REGISTRY_EXPORT = $(REGISTRY)/plugin/v2/recipes.json
SHELL := /bin/bash

.PHONY: test sync sync-check check bundle

BUNDLE = dist/omarchy-local-ai-$(shell jq -r .version manifest.json).tar.gz
RUNTIME = manifest.json recipes.json local-ai.policy LICENSE Panel.qml Model.js lfm.svg qwen.svg hf.svg bin/omarchy-local-ai bin/omarchy-install-ai-local bin/omarchy-remove-ai-local

test:
	bash test/all

# "Published" means the file committed at the registry's origin/main, not a checkout's working tree.
export_ = if git -C "$(REGISTRY)" rev-parse --verify --quiet "$(REGISTRY_REF)" >/dev/null 2>&1; then git -C "$(REGISTRY)" show "$(REGISTRY_REF):plugin/v2/recipes.json"; else cat "$(REGISTRY_EXPORT)"; fi
commit = $$(git -C "$(REGISTRY)" rev-parse "$(REGISTRY_REF)" 2>/dev/null || git -C "$(REGISTRY)" rev-parse HEAD)
# the registry lists each kind's recipes best first: the bundle keeps every one, one card first, in that order, so the
# first is a card's recommended model and the rest are what its Config offers (a group: one model across several cards)
published = $(export_) | jq -r --arg c "$(commit)" '.hardware |= map_values(.recipes |= sort_by(.cards // 1)) | .registryCommit = $$c \
  | (del(.hardware) | tojson | .[:-1]) + ",\"hardware\":{\n" + ([.hardware | to_entries[] | "\(.key | tojson):\(.value | tojson)"] | join(",\n")) + "\n}}"'
PROVENANCE = del(.registryCommit, .generatedAt)

sync:
	@test -d "$(REGISTRY)" || { echo "sync: set REGISTRY=<registry checkout>" >&2; exit 2; }
	@$(published) > recipes.json
	@jq -r '"recipes.json: \(.hardware|length) card kinds, registry \(.registryCommit[:12])"' recipes.json

sync-check:
	@test -d "$(REGISTRY)" || { echo "sync-check: set REGISTRY=<registry checkout>" >&2; exit 2; }
	@T=$$(mktemp); trap 'rm -f "$$T"' EXIT; $(published) > "$$T"; \
	if [ "$$(jq -S '$(PROVENANCE)' "$$T")" = "$$(jq -S '$(PROVENANCE)' recipes.json)" ]; then \
	  echo "recipes.json: current with the registry, $$(jq -r '.hardware|length' recipes.json) hardware ids"; \
	else \
	  echo "recipes.json has fallen behind the registry's published export; run make sync" >&2; \
	  diff <(jq -rS '$(PROVENANCE) | .hardware | keys[]' "$$T") <(jq -rS '$(PROVENANCE) | .hardware | keys[]' recipes.json) | grep -E '^[<>]' | sed 's/^/  /' >&2 || true; \
	  exit 1; \
	fi

check: test
	@jq -e '.schemaVersion=="omarchy-local-ai/recipes/2" and (.registryCommit|test("^[0-9a-f]{40}$$")) and (.gateway.image|test("@sha256:[0-9a-f]{64}$$")) and (.hardware|length>0) and all(.hardware[].recipes[]; (.image|test("@sha256:[0-9a-f]{64}$$")) and (.launch|has("ipc")|not))' recipes.json >/dev/null \
	  && echo "recipes.json: ok" || { echo "recipes.json: not a clean schema-2 export" >&2; exit 1; }
	@if [ -f "$(REGISTRY_EXPORT)" ]; then $(MAKE) --no-print-directory sync-check; \
	 else echo "recipes.json: registry not checked out at $(REGISTRY); the currency check was skipped"; fi

bundle:
	mkdir -p dist
	COPYFILE_DISABLE=1 tar -czf $(BUNDLE) $(RUNTIME)
