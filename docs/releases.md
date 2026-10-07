# Catalog releases

The registry owns recipes. Refresh models reaches its published export between plugin releases.
Vendor semantic catalog changes in a normal release PR with `make sync REGISTRY=<checkout>`, then
`make check`. Commit-only changes in the registry do not require a plugin release.

The manually dispatched `registry` workflow checks both sources and provides a patch artifact when
catalog content changes. Apply that artifact on the recorded plugin base. Normal PR CI and branch
protection apply; the workflow cannot push branches or create check statuses.

Tag the reviewed release commit and verify its archive before submitting that exact commit to the
marketplace. Keep repository HEAD on that release during marketplace review.
