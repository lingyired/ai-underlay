#!/usr/bin/env bash
# Captures the real menu-bar strip (whole screen grab, then a 2048x60pt @2x crop).
# usage: capture.sh <output-dir> <seconds>
set -euo pipefail
out="$1"; seconds="${2:-10}"
mkdir -p "$out/Frames"
rm -f "$out/Frames"/*.png
start=$(python3 -c 'import time;print(time.time())')
i=0
while :; do
  now=$(python3 -c 'import time;print(time.time())')
  elapsed=$(python3 -c "print($now-$start)")
  python3 -c "import sys;sys.exit(0 if $elapsed < $seconds else 1)" || break
  screencapture -x /tmp/aiunderlay-full.png
  cp /tmp/aiunderlay-full.png "$out/Frames/frame_$(printf '%04d' $i).png"
  i=$((i+1))
done
echo "captured $i frames in $out/Frames"
