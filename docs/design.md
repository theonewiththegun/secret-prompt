# Design

Why secret-prompt is built the way it is.
The whole point is that a secret goes from the user into the command that needs it and **never through the agent**: whatever a command prints lands in the agent's transcript, so nothing here ever prints a secret except the panel itself, to its caller.

## The three commands

- `secret-prompt` is the panel: it prints the secret to stdout and exits 0, or exits 1 on cancel and 2 on bad arguments.
  `with-secret` tells the two apart: only exit 1 is reported as a cancel, anything else as `secret-prompt failed with exit N` with that code, so a crash or a missing window server never reads as the user's choice.
  That is what makes it a building block and not a tool, and why the README asks for a deny rule on it.
  `asudo` and `with-secret` call it as child processes, which a permission rule does not see.
- `asudo [--reason TEXT] -- CMD...` runs `/usr/bin/sudo -A -- CMD...` with an askpass that opens the panel; the `--` keeps a command starting with `-` from being read as a sudo option such as `-s`.
- `with-secret (--env VAR | --stdin) [--title T] [--message M] [--placeholder P] -- CMD...` hands the value to `CMD` alone.
  `--env` exports it and `exec`s the command, so it lives in that one process's environment; `--env secret` works too, although `secret` is the script's own variable.
  `--stdin` pipes it from the `printf` builtin followed by a newline, because a bash here-string can be backed by a temp file on disk.
  Neither puts it in argv, which any user can read with `ps`.

Both scripts look for the panel next to themselves first, then on `PATH`, and say so when neither has it, rather than failing silently under `set -e`.
They run under macOS's `/bin/bash` 3.2, since that is what a brew or make install gets; `tests/run.sh` runs them under it.

## Wrong passwords

sudo calls its askpass once per attempt with the same prompt, so the panel cannot tell a retry from a first ask.
`asudo` therefore writes a throwaway askpass script (mode 700, in a `mktemp -d` removed on exit) that counts its own calls and passes `--error "Wrong password, try again"` from the second one on.
The panel shakes when it opens with an error.

## The command line shown

It is re-quoted for reading, not `%q`-escaped: plain words bare, anything else in single quotes, or double quotes when that avoids `'\''`.
It is never executed, so it only has to be unambiguous to a person.

## The panel

`Sources/main.swift` is an accessory AppKit app: no Dock icon, it comes to the front and takes the keyboard, Return submits and Escape cancels.

- **Reveal.** The eye, or ⌘⇧H, shows what was typed and hides it again.
  `NSSecureTextField` cannot display its text, so it is two fields swapped, and the hidden one is emptied so the value lives in one place.
  The shortcut is `"H"` with ⌘ alone, not `"h"` with ⌘⇧: AppKit does not strip Shift from the characters it matches, so the second never fires.
- **Secure input.** `NSSecureTextField` turns on secure event input while it has focus, so no other process can read the keystrokes; the plain field does not.
  The panel calls `EnableSecureEventInput()` itself for its whole lifetime, so revealing the value does not open it to keyloggers.
- **Crashes.** `NSApplicationCrashOnExceptions` is on, because AppKit otherwise logs an exception raised during setup and carries on with an invisible panel that sudo would wait on forever; a crash fails the caller instead.
- **Capture.** The window's `sharingType` is `.none`, so it is left out of screenshots and screen sharing.
  `SECRET_PROMPT_CAPTURABLE=1` lifts that, and sudo passes the variable through to the askpass.
- **Rounded blur.** A behind-window `NSVisualEffectView` is blurred by the window server over its whole rectangle, so the rounded corners come from its `maskImage`; a layer `cornerRadius` leaves a square outline and shadow.

## Theme

`Sources/Theme.swift` reads `key = value` lines by hand, so there is no dependency to install.
A `#` starts a comment at the start of a line, or after whitespace inside a value; a color's own `#` follows the `=` directly, so the two do not collide.
The preset applies first wherever its line sits, then every override on top, so the order of lines in the file does not matter.
Each preset carries a dark or light flag that sets the panel's `NSAppearance`; without it the blur under Latte stays dark.
A bad line warns on stderr and is skipped: the file is read on every sudo prompt, and a typo in it must not be what stops one from appearing.

Colors that the panel draws translucent (the tint, the wells, the border) multiply their own alpha into the one the user gave, so `#RRGGBBAA` still means something there.
