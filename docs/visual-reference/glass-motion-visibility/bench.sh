#!/usr/bin/env bash
# Matched-fixture CPU/RSS probe for the Glass Spectrum motion pass.
#
# Same display, same fixture, same build settings: run it once against this
# branch's app and once against the fidelity-fix baseline app (AIUNDERLAY_APP=…)
# to compare the animated curtain with the old bed/peak/mask tree.
#
# usage: bench.sh <out-dir> <seconds> <variant>
#        AIUNDERLAY_APP=/path/to/AIUnderlay.app bench.sh out 60 bench-running
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/menu-fixture.sh"

out="${1:?usage: bench.sh <out-dir> <seconds> <variant>}"
seconds="${2:?usage: bench.sh <out-dir> <seconds> <variant>}"
variant="${3:-bench-running}"

assert_unlocked
require_tools
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

kill_app
write_variant_settings "$variant" "$backup"
start_app
pid="$(pgrep -f "$APP/Contents/MacOS/AIUnderlay" | head -1)"
echo "sampling pid $pid for ${seconds}s"

samples="$out/$variant.csv"
echo "t,cpu_percent,rss_kb" > "$samples"
for ((i = 0; i < seconds; i++)); do
  ps -o %cpu=,rss= -p "$pid" | awk -v t="$i" '{ print t "," $1 "," $2 }' >> "$samples"
  sleep 1
done

python3 - "$samples" <<'PY'
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
cpu = [float(r["cpu_percent"]) for r in rows]
rss = [int(r["rss_kb"]) for r in rows]
def p95(values):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(0.95 * (len(values) - 1))))]
print(f"samples {len(rows)}")
print(f"cpu  mean {statistics.mean(cpu):6.2f}%  p95 {p95(cpu):6.2f}%  max {max(cpu):6.2f}%")
print(f"rss  mean {statistics.mean(rss)/1024:6.1f} MiB  max {max(rss)/1024:6.1f} MiB")
PY

restore
trap - EXIT
