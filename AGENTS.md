# AGENTS.md

secret-prompt: a macOS panel that asks the user for a secret on an agent's behalf, with `asudo` and `with-secret` on top.

## Start

```sh
make                                   # build/secret-prompt, universal
build/secret-prompt --title Test       # the panel itself; Escape to close
```

## Verify

```sh
make test       # tests/run.sh under /bin/bash 3.2, against a stub panel
make lint       # shellcheck
nix flake check # the same tests under bash 5 against the nix build
```

The panel's look and the real sudo path are manual: `scripts/screenshots.sh` regenerates `docs/screenshots/`, and `asudo --reason test -- true` exercises the rest.

## Topics

| Topic | File |
| --- | --- |
| Why it is built this way | `docs/design.md` |
| What a user observes, and how each row is checked | `docs/behavior/panel.md` |

## Releasing

Bump `version` in `nix/package.nix`, tag `vX.Y.Z`, `gh release create`, then update `url` and `sha256` in `Formula/secret-prompt.rb` of `theonewiththegun/homebrew-tap`.
