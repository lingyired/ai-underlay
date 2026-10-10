#!/usr/bin/env bash
# Runs the full test suite headlessly.
set -euo pipefail
cd "$(dirname "$0")/.."
exec xcodebuild -scheme AIUnderlay -destination 'platform=macOS' test "$@"
