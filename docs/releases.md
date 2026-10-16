# Releases

`main` is the default branch and carries releases only. Omarchy installs and updates a plugin from its default
branch (`omarchy plugin add`, `omarchy plugin update`), and the marketplace verifies its current commit, so `main`
moves once per release and stays still while the marketplace reviews it. Everything else lands on `dev`.

## Work

Open pull requests against `dev`. CI runs on both branches; a pull request to `main` from any branch other than
`dev` fails the `base` check.

## What needs a release

Code, and every new or changed launch. Between releases a refresh can only withdraw or relabel shipped recipes:
the panel checks the registry every 12 hours and keeps a recipe from its export only when this release ships a
recipe with the same id, on the same card kind, that runs exactly the same (image, launch, weights, asset, scratch,
preparation, cards, minimum driver, served name; `registry` in the backend). New recipes, new or changed launches and
a new gateway ship with a release; vendor them with `make sync REGISTRY=<checkout>` and `make check`. The manually dispatched `registry` workflow tells you whether
the catalog content changed and gives a patch for that sync.

## Cutting one

1. On `dev`: bump `manifest.json`, add the `CHANGELOG.md` section, and sync recipes if the release needs them.
2. Open the release pull request `dev` -> `main` titled `release X.Y.Z: <what changed>` and squash-merge it.
3. Tag `vX.Y.Z` on that commit and push the tag. `release.yml` checks the tag, runs the suite, publishes the
   release with its archive, and merges `main` back into `dev` so the next release pull request shows only new work.
4. Marketplace: when no verify request is open, file one for the exact new `main` commit. While one is open, do
   not release; batch the work on `dev` until it is published. A reviewer's blocker is the only reason to release
   into an open request.

Installed copies see a release by themselves: the panel's update check (`outdated`, every 6 hours) compares the
checkout with `main` and offers **Update Local AI** on the home page, which runs `omarchy plugin update`.
