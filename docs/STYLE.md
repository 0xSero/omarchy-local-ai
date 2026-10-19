# How to write docs here

For anyone, person or agent, changing README.md or docs/.

## Where things go

| Page | Reader | Holds |
|---|---|---|
| `README.md` | Someone installing | What it is, install, first run, supported cards, commands, remove. Nothing else. |
| `docs/troubleshooting.md` | Someone with an error | The exact message, then what to do. |
| `docs/security.md`, `docs/privacy.md` | Someone checking what it touches | What setup changes, isolation, what is sent. |
| `docs/catalog.md` | Someone curious about updates | How models arrive, downloads, removal. |
| `docs/design.md`, `docs/releases.md` | Contributors | How it works inside, branches and releases. |
| `CHANGELOG.md` | Anyone | What changed in each version. Version history goes here and nowhere else. |

A new error message the panel can show gets an entry in `troubleshooting.md` in the same pull request.

## Writing

- Open each page with one line saying who it is for.
- Short sentences, one idea each. Split a sentence with a semicolon into two.
- Steps are numbered and start with a verb: "Click **Start**."
- Say what the user sees and does. Put how it works inside in `design.md`.
- Quote messages exactly as the panel shows them. In troubleshooting.md each message is a `###` heading, so it can be linked.
- Give commands in code blocks the reader can paste.
- No version numbers in user docs except where a version matters to the reader (the polkit page).

## Generated and checked

- The supported-hardware table in the README is written by `make docs` from `recipes.json` (`make sync` runs it).
  Never edit it by hand.
- `test/docs-test.sh` fails when that table is stale, a link or heading anchor is broken, the README shows a command
  the backend does not have, or a page in `docs/` is not linked from the README.
- `test/listing-test.sh` keeps the install command in the README's first 15 lines and in the store description.
- The marketplace scanner reads everything outside `docs/` and `test/`, so `sudo`, `systemctl` and `pkexec` may appear
  only in `docs/` (`test/setup-test.sh` checks).
