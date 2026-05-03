#!/usr/bin/env bash
set -euo pipefail
# Bitnami chart создаёт secret <release>-pg-<svc>
for svc in resource-manager vpc compute loadbalancer; do
  kubectl -n kacho get secret kacho-umbrella-pg-${svc} >/dev/null
done
echo "PASS: E5 — all 4 db-credential secrets present"
