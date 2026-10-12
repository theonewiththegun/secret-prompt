#!/usr/bin/env bash
# Single quotes around $ are deliberate throughout: the child shell expands them.
# shellcheck disable=SC2016

# tests/run.sh [PATH-TO-secret-prompt]
#
# CLI tests for the theme loader and for with-secret/asudo. The scripts run
# under $TEST_BASH (default /bin/bash, the 3.2 that brew and make installs get),
# against a stub panel, so nothing here opens a window or needs a password.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
panel=$(cd "$(dirname "${1:-$root/build/secret-prompt}")" && pwd)/$(basename "${1:-secret-prompt}")
test_bash=${TEST_BASH:-/bin/bash}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  shift
  printf '      %s\n' "$@"
  failures=$((failures + 1))
}
expect_eq() {
  if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1" "expected: $3" "got:      $2"; fi
}
expect_has() {
  if [[ $2 == *"$3"* ]]; then pass "$1"; else fail "$1" "expected to contain: $3" "got: $2"; fi
}

# --- theme -------------------------------------------------------------------

conf=$work/config
theme() { printf '%s\n' "$@" >"$conf"; SECRET_PROMPT_CONFIG=$conf "$panel" --dump-theme 2>"$work/stderr"; }
key() { grep "^$1 = " | sed "s/^$1 = //"; }

out=$(SECRET_PROMPT_CONFIG=$work/missing "$panel" --dump-theme)
expect_eq "no config file: mocha" "$(key theme <<<"$out")" catppuccin-mocha
expect_has "no config file: says so" "$out" "(not found, defaults shown)"
expect_eq "no config file: mocha accent" "$(key accent <<<"$out")" "#CBA6F7"

for preset in mocha:dark:#CBA6F7 macchiato:dark:#C6A0F6 frappe:dark:#CA9EE6 latte:light:#8839EF; do
  IFS=: read -r name look accent <<<"$preset"
  out=$(theme "theme = catppuccin-$name")
  expect_eq "preset $name: appearance" "$(key appearance <<<"$out")" "$look"
  expect_eq "preset $name: accent" "$(key accent <<<"$out")" "$accent"
done

out=$(theme "accent = #ff0000" "theme = catppuccin-latte")
expect_eq "override above the theme line still wins" "$(key accent <<<"$out")" "#FF0000"
expect_eq "override keeps the rest of the preset" "$(key background <<<"$out")" "#EFF1F5"

out=$(theme "error = #FF000080" "text = 00FF00" 'muted = "#123456"')
expect_eq "#RRGGBBAA keeps its alpha" "$(key error <<<"$out")" "#FF000080"
expect_eq "hex without #" "$(key text <<<"$out")" "#00FF00"
expect_eq "quoted value" "$(key muted <<<"$out")" "#123456"

out=$(theme "# a comment" "" "  opacity = 0.8  " "appearance = light")
expect_eq "opacity" "$(key opacity <<<"$out")" "0.80"
expect_eq "appearance override" "$(key appearance <<<"$out")" light

out=$(theme "accent = purple")
expect_eq "bad hex falls back" "$(key accent <<<"$out")" "#CBA6F7"
expect_has "bad hex warns with the line" "$(cat "$work/stderr")" "$conf:1: accent must be #RRGGBB or #RRGGBBAA, got 'purple', ignored"

out=$(theme "theme = dracula" "colour = #000000" "opacity = 2" "nonsense")
expect_eq "unknown theme falls back to mocha" "$(key theme <<<"$out")" catppuccin-mocha
warnings=$(cat "$work/stderr")
expect_has "unknown theme warns" "$warnings" ":1: unknown theme 'dracula'"
expect_has "unknown key warns" "$warnings" ":2: unknown key 'colour'"
expect_has "opacity out of range warns" "$warnings" ":3: opacity must be a number from 0 to 1"
expect_has "line without = warns" "$warnings" ":4: expected key = value"

out=$(theme "theme = catppuccin-latte   # a comment after a value" "accent = #89B4FA # and one after a color")
expect_eq "comment after a value" "$(key theme <<<"$out")" catppuccin-latte
expect_eq "comment after a color" "$(key accent <<<"$out")" "#89B4FA"
expect_eq "comments do not warn" "$(cat "$work/stderr")" ""

mkdir -p "$work/xdg/secret-prompt"
echo "theme = catppuccin-frappe" >"$work/xdg/secret-prompt/config"
out=$(env -u SECRET_PROMPT_CONFIG XDG_CONFIG_HOME="$work/xdg" "$panel" --dump-theme)
expect_eq "XDG_CONFIG_HOME is read" "$(key theme <<<"$out")" catppuccin-frappe

out=$(theme "theme = system")
case $(key theme <<<"$out") in
  catppuccin-mocha | catppuccin-latte) pass "system resolves to mocha or latte" ;;
  *) fail "system resolves to mocha or latte" "got: $out" ;;
esac

set +e
"$panel" --bogus x 2>"$work/stderr"
code=$?
set -e
expect_eq "unknown panel option exits 2" "$code" 2

# --- scripts -----------------------------------------------------------------

# A stub panel next to the scripts, the layout make and brew install.
bin=$work/bin
mkdir -p "$bin"
cp "$root/bin/asudo" "$root/bin/with-secret" "$bin/"
cat >"$bin/secret-prompt" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$STUB_ARGS"
[ -n "${STUB_EXIT:-}" ] && exit "$STUB_EXIT"
echo 's3cret'
EOF
chmod 755 "$bin/secret-prompt"
export STUB_ARGS=$work/args

run() { "$test_bash" "$bin/$1" "${@:2}"; }

expect_eq "with-secret --env hands the value to the command" \
  "$(run with-secret --env TOKEN -- sh -c 'printf %s "$TOKEN"')" s3cret
expect_eq "with-secret --stdin feeds it with a newline" \
  "$(run with-secret --stdin -- od -An -tx1 | tr -d ' \n')" "7333637265740a"
expect_eq "with-secret leaves other variables alone" \
  "$(TOKEN=outer run with-secret --env OTHER -- sh -c 'printf %s "$TOKEN"')" outer

run with-secret --env X --title "API token" --message why --placeholder Token -- true
args=$(cat "$STUB_ARGS")
expect_has "with-secret passes --title" "$args" $'--title\nAPI token'
expect_has "with-secret passes --message" "$args" $'--message\nwhy'
expect_has "with-secret passes --placeholder" "$args" $'--placeholder\nToken'

run with-secret --env X -- echo plain 'a b' "it's" 'x$y' "a'\$b" >/dev/null
expect_eq "displayed command is quoted for reading" \
  "$(sed -n '/^--command$/{n;p;}' "$STUB_ARGS")" "echo plain 'a b' \"it's\" 'x\$y' 'a'\\''\$b'"

set +e
STUB_EXIT=1 run with-secret --env X -- touch "$work/ran" 2>"$work/stderr"
code=$?
set -e
expect_eq "cancel exits 1" "$code" 1
expect_eq "cancel says what was not run" "$(cat "$work/stderr")" "with-secret: cancelled, touch was not run"
if [[ -e $work/ran ]]; then fail "cancel does not run the command"; else pass "cancel does not run the command"; fi

set +e
STUB_EXIT=3 run with-secret --env X -- touch "$work/ran" 2>"$work/stderr"
code=$?
set -e
expect_eq "a failing panel keeps its exit code" "$code" 3
expect_eq "a failing panel is not called a cancel" "$(cat "$work/stderr")" \
  "with-secret: secret-prompt failed with exit 3, touch was not run"

expect_eq "--env secret, the script's own variable name" \
  "$(run with-secret --env secret -- sh -c 'printf %s "$secret"')" s3cret

body() { sed -n '/^display() {$/,/^}$/p' "$root/bin/$1"; }
expect_eq "asudo and with-secret quote the command the same way" "$(body asudo)" "$(body with-secret)"

for bad in "--env" "--env 1BAD -- true" "-- true" "--stdin" "--frob -- true"; do
  set +e
  # shellcheck disable=SC2086 # word splitting is the point
  run with-secret $bad 2>/dev/null
  code=$?
  set -e
  expect_eq "with-secret $bad: usage error" "$code" 2
done

for bad in "" "--reason" "--frob true"; do
  set +e
  # shellcheck disable=SC2086
  run asudo $bad 2>/dev/null
  code=$?
  set -e
  expect_eq "asudo $bad: usage error" "$code" 2
done

# Without a panel beside it or on PATH, the scripts say so instead of exiting silently.
lone=$work/lone
mkdir -p "$lone"
cp "$root/bin/with-secret" "$lone/"
set +e
PATH=/usr/bin:/bin "$test_bash" "$lone/with-secret" --env X -- true 2>"$work/stderr"
code=$?
set -e
expect_eq "missing panel exits 127" "$code" 127
expect_has "missing panel says so" "$(cat "$work/stderr")" "secret-prompt is neither next to this script nor on PATH"

echo
if ((failures)); then
  echo "$failures failed"
  exit 1
fi
echo "all passed ($("$test_bash" -c 'echo "bash $BASH_VERSION"'))"
