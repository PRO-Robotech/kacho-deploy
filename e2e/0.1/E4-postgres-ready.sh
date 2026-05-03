#!/usr/bin/env bash
set -euo pipefail
PODS=$(kubectl -n kacho get pods -l 'app.kubernetes.io/name=postgresql' -o jsonpath='{.items[*].metadata.name}')
COUNT=$(echo "$PODS" | wc -w)
[ "$COUNT" -eq 4 ] || { echo "FAIL: expected 4 postgres pods, got $COUNT"; exit 1; }

for pod in $PODS; do
  kubectl -n kacho wait --for=condition=ready pod/"$pod" --timeout=180s
done

# Каждая БД доступна и пуста
declare -A DBS=(
  [pg-resource-manager-0]="resource_manager kacho_resource_manager"
  [pg-vpc-0]="vpc kacho_vpc"
  [pg-compute-0]="compute kacho_compute"
  [pg-loadbalancer-0]="loadbalancer kacho_loadbalancer"
)
for pod in "${!DBS[@]}"; do
  read -r user db <<< "${DBS[$pod]}"
  count=$(kubectl -n kacho exec "$pod" -- psql -U "$user" -d "$db" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
  [ "$count" = "0" ] || { echo "FAIL: $db has $count user tables (expected 0)"; exit 1; }
done

echo "PASS: E4 — 4 postgres ready, all DBs empty"
