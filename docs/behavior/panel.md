# Behaviour: the panel

What somebody sees when an agent, or a script, asks for a secret through `asudo` or `with-secret`.
The mechanism is in [`docs/design.md`](../design.md).

| Scenario | What they observe | Verified by |
| --- | --- | --- |
| `asudo --reason "..." -- <cmd>` | A translucent panel, "Administrator password", with the reason and the command line as typed. The right password runs the command; nothing about it appears in the caller's output | manual |
| A wrong password in that panel | The panel comes back with "Wrong password, try again" in the error color and a shake; sudo allows its usual three attempts | manual |
| Escape or Cancel in that panel | The command does not run, and sudo keeps no credentials: the caller sees `no password was provided` | manual |
| `with-secret --env VAR --title "..." -- <cmd>` | A panel with a key icon, the title and the command line; the command receives the value as `VAR` | `tests/run.sh` (stub panel); manual for the real one |
| The same with `--stdin` | The command reads the value from its stdin, with a trailing newline | `tests/run.sh` |
| Escape on a `with-secret` panel | `with-secret: cancelled, <cmd> was not run`, exit 1, the command never starts | `tests/run.sh` |
| `with-secret` or `asudo` with bad arguments | A usage line, exit 2 | `tests/run.sh` |
| The panel is neither next to the script nor on `PATH` | `<script>: secret-prompt is neither next to this script nor on PATH`, exit 127 | `tests/run.sh` |
| You want to check what you typed | The eye at the end of the field, or ⌘⇧H, shows the value; again hides it. What you typed survives either way, and Return sends it from whichever state | manual |
| A screenshot or screen share while a panel is open | The panel is not in it | manual |
| No config file | Catppuccin Mocha | `tests/run.sh` |
| `theme = catppuccin-latte` (or macchiato, frappe) | That palette, with a light blur for Latte | `tests/run.sh` for the palette; `scripts/screenshots.sh` for the look |
| `theme = system` | Latte in light mode, Mocha in dark | `tests/run.sh` (resolves to one of the two); manual for the switch |
| A role override such as `accent = #89B4FA` | That color, wherever the line sits relative to `theme` | `tests/run.sh` |
| A bad line in the config | `secret-prompt: <path>:<line>: <what is wrong>, ignored` on stderr, and the panel still appears with that key at its default | `tests/run.sh` |
| `secret-prompt --dump-theme` | The palette in effect, as config lines, headed by the file path and whether it exists | `tests/run.sh` |
