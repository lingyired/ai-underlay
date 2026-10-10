#!/usr/bin/env bash
# Enforces dependency rule 1: Domain/ must not import AppKit / SwiftUI / CodexBar.
# Usage: Scripts/check-domain-purity.sh   (exit 0 = clean, 1 = violation)
set -euo pipefail

DOMAIN_DIR="$(cd "$(dirname "$0")/.." && pwd)/AIUnderlayKit/Domain"

if [ ! -d "$DOMAIN_DIR" ]; then
  echo "check-domain-purity: no Domain directory yet, skipping"
  exit 0
fi

violations=$(grep -REn '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|CodexBar)' "$DOMAIN_DIR" || true)

if [ -n "$violations" ]; then
  echo "check-domain-purity: VIOLATION — Domain must not import UI/data-source modules:"
  echo "$violations"
  exit 1
fi

echo "check-domain-purity: OK"
