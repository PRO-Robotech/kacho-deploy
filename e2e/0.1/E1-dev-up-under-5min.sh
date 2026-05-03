#!/usr/bin/env bash
set -euo pipefail
START=$(date +%s)
make dev-down >/dev/null 2>&1 || true
make dev-up
END=$(date +%s)
ELAPSED=$((END - START))
echo "dev-up took ${ELAPSED}s"
[ $ELAPSED -lt 300 ] || { echo "FAIL: dev-up took ${ELAPSED}s (>= 300s)"; exit 1; }
echo "PASS: E1"
