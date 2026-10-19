# Catalog, downloads and removal

New models, and any change to how a model runs, come with plugin updates, which
the panel offers on home. Between updates, once the catalog is 12 hours old,
Local AI checks the latest published registry (at most once an hour) and says so
only when it changed the list; the catalog lives in your cache
(`~/.cache/omarchy/local-ai/v4`). A refresh can only withdraw, reorder or relabel
the recipes the plugin ships: each recipe it lists that the plugin's own
`recipes.json` has (same id, same card kind) becomes that shipped recipe, and only
its name, family, format, size, score and capability flags are taken from the
registry, each when it is short plain text, a finite number or a boolean.
Everything that decides what runs or how an agent is set up (image, launch,
weights, context, needs and the rest) is always the shipped recipe's, and a recipe
the plugin does not ship is left out until a plugin update ships it. Downloads are
pinned to a registry commit, validated before an atomic replacement, and failures
keep the previous catalog. A catalog an earlier version refreshed is not read; a
refresh installs a catalog only once the panel can be drawn from it, and a catalog
that later cannot be read or drawn is skipped for the shipped recipes (the log
says why) until the next refresh replaces it. A model whose recipe an update withdrew keeps Stop; its download,
and any folder no recipe here uses, is listed on home under **No longer offered**
with **Remove**.
Refreshing does not stop running models or download model weights. Offload
recipes are offered only when their RAM, disk and storage requirements fit.

A recipe that generates a pack first declares its output budget separately from
raw weights. Local AI prepares with the pinned serving image, verifies the pack
and publishes it from private staging. Each reuse is verified. Stop retains the
completed pack; Remove download removes it only when no managed model uses it.
The v3 contract supports these operations; research models still require their
own accepted image, hardware and fidelity evidence before they appear here.

On the models tab, open a model's row to **Start** it, **Download** it without
starting, **Pin** it to home, or see its details. **Remove download** deletes that model's managed weights after it is stopped;
shared weights in use by another managed model are protected. The recipe stays
available to download again. Files in your separate Hugging Face cache are kept,
so hard-linked files there may continue to occupy disk space.

The equivalent commands are `omarchy-local-ai registry`, `download <recipe> [off]`,
`pin <recipe> [off]` and `forget <recipe>` (or the plugin's `bin/omarchy-local-ai`).

