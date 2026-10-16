#!/usr/bin/env bash
# What survives the menu bar's material?
#
# A lane is composited *through* the system menu bar material, so the colour we
# draw is never the colour on screen. This probe answers "by how much" with a
# controlled signal: it repaints the waiting top line in known flat colours,
# captures the real bar, and writes the measured sRGB values next to what was
# asked for.
#
# usage: probe-material-transfer.sh <out-dir> [colour ...]
# default colours: #FFFFFF #FF0000 #00FF00 #0000FF #FFE1A0
#
# The user's own settings.json is backed up first and restored on exit, also
# on failure. The screen must be unlocked.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../glass-motion-visibility/menu-fixture.sh"

out="${1:?usage: probe-material-transfer.sh <out-dir> [colour ...]}"
shift || true
colours=("$@")
[ "${#colours[@]}" -gt 0 ] || colours=("#FFFFFF" "#FF0000" "#00FF00" "#0000FF" "#FFE1A0")

assert_unlocked
mkdir -p "$out"
backup="$out/settings-backup.json"
backup_settings "$backup"

restore() {
  if [ -f "$backup" ]; then
    cp "$backup" "$SETTINGS"
    relaunch_app || true
    echo "restored the user's settings from $backup"
  fi
}
trap restore EXIT

for colour in "${colours[@]}"; do
  name="waiting-${colour#\#}"
  kill_app
  PROBE_COLOUR="$colour" python3 - "$backup" "$SETTINGS" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as fh:
    settings = json.load(fh)
settings["previewFixture"] = "agentWaiting"
settings["showAgentEffects"] = True
settings["overlayEnabled"] = True
settings["reduceMotion"] = False
appearance = settings.setdefault("appearance", {})
appearance["signalColors"] = {"waiting": os.environ["PROBE_COLOUR"]}
with open(dst, "w") as fh:
    json.dump(settings, fh)
PY
  start_app
  screencapture -x -o "$out/$name.png"
  echo "captured $colour -> $out/$name.png"
done

restore
trap - EXIT
echo "done: $out"
