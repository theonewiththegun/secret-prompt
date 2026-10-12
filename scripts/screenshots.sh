#!/usr/bin/env bash
# scripts/screenshots.sh [PATH-TO-secret-prompt]
#
# Regenerates docs/screenshots/*.png. Needs a logged-in GUI session and the
# Screen Recording permission for the terminal; the panel is made capturable
# for the run, since by default it is excluded from every screenshot.

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
panel=${1:-$root/build/secret-prompt}
out=$root/docs/screenshots
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

# CGWindowList is the only way to a window id; screencapture -l needs one.
cat >"$work/winid.swift" <<'EOF'
import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
if let id = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid })?[kCGWindowNumber as String] {
    print(id)
}
EOF
swiftc -o "$work/winid" "$work/winid.swift"

shoot() {
  local name=$1 theme=$2
  shift 2
  printf 'theme = %s\n' "$theme" >"$work/config"
  SECRET_PROMPT_CAPTURABLE=1 SECRET_PROMPT_CONFIG=$work/config "$panel" "$@" >/dev/null &
  local pid=$! id="" _
  for _ in $(seq 50); do
    id=$("$work/winid" "$pid")
    [[ -n $id ]] && break
    sleep 0.1
  done
  [[ -n $id ]] || { echo "no window for $name" >&2; kill "$pid"; exit 1; }
  sleep 1 # the fade-in, and the shake on the error state
  screencapture -x -l"$id" "$out/$name.png"
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  echo "$out/$name.png"
}

asudo=(--title "Administrator password" --button Authenticate --placeholder Password
  --message "Restart sshd to pick up the new config"
  --command "launchctl kickstart -k system/com.openssh.sshd")

shoot asudo catppuccin-mocha "${asudo[@]}"
shoot wrong-password catppuccin-mocha "${asudo[@]}" --error "Wrong password, try again"
shoot with-secret catppuccin-mocha --title "GitHub token" --icon key.fill --placeholder Token \
  --command "gh auth login --with-token"
shoot latte catppuccin-latte "${asudo[@]}"
