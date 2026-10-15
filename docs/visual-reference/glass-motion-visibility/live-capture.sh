#!/usr/bin/env bash
# Live menu-bar recording for the Glass Spectrum motion pass.
#
# For every variant this writes a preview-fixture settings file, relaunches the
# worktree app, records the real menu-bar strip at 30 fps, then — always, also
# on failure — restores the user's own settings.json and relaunches the app.
#
# usage: live-capture.sh <out-dir> <seconds> [variant ...]
# variants: traveling-on traveling-off tempo-050 tempo-090 tempo-110
#           agent-waiting agent-error agent-running-waiting agent-running-error
#           agent-running-unread agent-all-signals
# default variants: traveling-on traveling-off tempo-050 tempo-090
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/menu-fixture.sh"

out="${1:?usage: live-capture.sh <out-dir> <seconds> [variant ...]}"
seconds="${2:?usage: live-capture.sh <out-dir> <seconds> [variant ...]}"
shift 2
variants=("$@")
[ "${#variants[@]}" -gt 0 ] || variants=(traveling-on traveling-off tempo-050 tempo-090)

assert_unlocked
require_tools
mkdir -p "$out"
backup="$out/settings-backup.json"
backup_settings "$backup"

read -r width height scale < <(strip_geometry)
device="$(screen_device_index)"
echo "strip ${width}x${height}px @${scale}x, avfoundation device $device"

restore() {
  if [ -f "$backup" ]; then
    cp "$backup" "$SETTINGS"
    relaunch_app || true
    echo "restored the user's settings from $backup"
  fi
}
trap restore EXIT

for variant in "${variants[@]}"; do
  echo "== $variant =="
  # The app must be down before its settings file is rewritten, so nothing can
  # flush the old values back over the fixture.
  kill_app
  write_variant_settings "$variant" "$backup"
  start_app
  video="$out/$variant.mp4"
  ffmpeg -hide_banner -loglevel error \
    -f avfoundation -framerate 30 -capture_cursor 0 -i "$device:none" \
    -t "$seconds" -vf "crop=$width:$height:0:0" -pix_fmt yuv420p -y "$video"
  # Three stills per clip: the fastest way to eyeball phase, crest position and
  # whether the system text is still readable.
  for fraction in 25 50 75; do
    ffmpeg -hide_banner -loglevel error -i "$video" \
      -vf "select='gte(t,$(python3 -c "print($seconds*$fraction/100)"))'" \
      -frames:v 1 -y "$out/$variant-${fraction}.png"
  done
  echo "recorded ${seconds}s -> $video"
done

restore
trap - EXIT
echo "done: $out"
