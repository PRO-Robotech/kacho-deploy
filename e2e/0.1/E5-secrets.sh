#!/usr/bin/env bash
set -euo pipefail
for svc in resource-manager vpc compute loadbalancer; do
  kubectl -n kacho get secret pg-${svc}-postgresql >/dev/null
done
echo "PASS: E5 — all 4 db-credential secrets present"
