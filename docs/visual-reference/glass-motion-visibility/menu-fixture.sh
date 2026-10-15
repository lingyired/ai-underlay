#!/usr/bin/env bash
# Shared helpers for the Glass Spectrum motion acceptance scripts.
#
# The point of these helpers is that every live check runs against the *same*
# production code path (`AppCoordinator` → `LaneRenderSpec` → renderer) with a
# deterministic preview fixture, and that the user's own `settings.json` is
# always put back, whatever happens in between.
#
# Source it, do not execute it:  . "$(dirname "$0")/menu-fixture.sh"

set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
APP="${AIUNDERLAY_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/AIUnderlay.app}"
SETTINGS="$HOME/Library/Application Support/com.lingsmbp.aiunderlay/settings.json"

# Fixture key and motion overrides per variant. Tempo values are Hz, exactly
# what the settings page writes.
variant_fixture() {
  case "$1" in
    traveling-on|traveling-off|tempo-*|bench-running) echo "agentRunning" ;;
    agent-waiting) echo "agentWaiting" ;;
    agent-error) echo "agentError" ;;
    agent-running-waiting) echo "agentRunningWaiting" ;;
    agent-running-error) echo "agentRunningError" ;;
    agent-running-unread) echo "agentRunningUnread" ;;
    agent-all-signals) echo "agentAllSignals" ;;
    *) echo "unknown variant: $1" >&2; return 1 ;;
  esac
}

variant_floor_hz() {
  case "$1" in
    tempo-050) echo "0.50" ;;
    tempo-090) echo "0.90" ;;
    tempo-110) echo "1.10" ;;
    *) echo "0.70" ;;
  esac
}

variant_travels() {
  case "$1" in
    traveling-off) echo "false" ;;
    *) echo "true" ;;
  esac
}

assert_unlocked() {
  if ioreg -n Root -d1 | grep -q 'CGSSessionScreenIsLocked"=Yes'; then
    echo "The screen is locked, so the menu bar is not composited and any" >&2
    echo "capture would show the lock screen. Unlock the Mac and rerun." >&2
    exit 1
  fi
}

backup_settings() {
  local backup="$1"
  mkdir -p "$(dirname "$backup")"
  cp "$SETTINGS" "$backup"
}

# write_variant_settings <variant> <base-json>
# The base file is the user's own settings; only the motion fields and the
# preview fixture are touched, so everything else (displays, themes, quota
# colours) stays exactly as the user had it.
write_variant_settings() {
  local variant="$1" base="$2"
  local fixture floor travels
  fixture="$(variant_fixture "$variant")"
  floor="$(variant_floor_hz "$variant")"
  travels="$(variant_travels "$variant")"
  VARIANT="$variant" FIXTURE="$fixture" FLOOR="$floor" TRAVELS="$travels" \
    python3 - "$base" "$SETTINGS" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as fh:
    settings = json.load(fh)
settings["previewFixture"] = os.environ["FIXTURE"]
settings["showAgentEffects"] = True
settings["overlayEnabled"] = True
settings["reduceMotion"] = False
settings["motionFloorFrequencyHz"] = float(os.environ["FLOOR"])
settings["motionIntensity"] = 0.75
settings["showTravelingLight"] = os.environ["TRAVELS"] == "true"
with open(dst, "w") as fh:
    json.dump(settings, fh)
PY
}

kill_app() {
  pkill -f "$APP/Contents/MacOS/AIUnderlay" >/dev/null 2>&1 || true
  sleep 1
}

start_app() {
  open "$APP"
  local waited=0
  until pgrep -f "$APP/Contents/MacOS/AIUnderlay" >/dev/null; do
    sleep 0.5
    waited=$((waited + 1))
    if [ "$waited" -gt 20 ]; then
      echo "app did not start from $APP" >&2
      return 1
    fi
  done
  # Give the overlay its first spec update and the ray sprites a moment to
  # rasterise before anything is recorded.
  sleep 4
}

relaunch_app() {
  kill_app
  start_app
}

require_tools() {
  for tool in ffmpeg swiftc python3; do
    command -v "$tool" >/dev/null || {
      echo "$tool is required but not on PATH" >&2
      exit 1
    }
  done
}

# Prints "<strip-width-px> <strip-height-px> <scale>": the menu-bar strip in
# device pixels, measured from the current display rather than assumed.
strip_geometry() {
  local helper="${TMPDIR:-/tmp}/aiunderlay-strip-geometry"
  if [ ! -x "$helper" ]; then
    cat > "$helper.swift" <<'SWIFT'
import AppKit
let screen = NSScreen.screens.first!
let scale = screen.backingScaleFactor
let strip = screen.frame.height - screen.visibleFrame.height
print("\(Int((screen.frame.width * scale).rounded())) \(Int((strip * scale).rounded())) \(Int(scale))")
SWIFT
    swiftc -O "$helper.swift" -o "$helper" >/dev/null
  fi
  "$helper"
}

# The avfoundation device index of the main display ("Capture screen 0").
screen_device_index() {
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 \
    | awk '/Capture screen/{ if (match($0, /\[[0-9]+\]/)) { print substr($0, RSTART+1, RLENGTH-2); exit } }'
}
