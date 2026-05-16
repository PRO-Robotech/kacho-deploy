#!/usr/bin/env bash
set -euo pipefail

# Bitnami chart 13.x labels: app.kubernetes.io/component=primary
# pod names: <release>-pg-<svc>-0  (release="kacho-umbrella")
PODS=$(kubectl -n kacho get pods -l 'app.kubernetes.io/component=primary,app.kubernetes.io/instance=kacho-umbrella' -o jsonpath='{.items[*].metadata.name}')
COUNT=$(echo "$PODS" | wc -w)
[ "$COUNT" -eq 3 ] || { echo "FAIL: expected 3 postgres pods, got $COUNT"; exit 1; }

for pod in $PODS; do
  kubectl -n kacho wait --for=condition=ready pod/"$pod" --timeout=180s
done

# Каждая БД доступна и пуста
declare -A DBS=(
  [kacho-umbrella-pg-resource-manager-0]="resource_manager kacho_resource_manager"
  [kacho-umbrella-pg-vpc-0]="vpc kacho_vpc"
  [kacho-umbrella-pg-compute-0]="compute kacho_compute"
)
for pod in "${!DBS[@]}"; do
  read -r user db <<< "${DBS[$pod]}"
  count=$(kubectl -n kacho exec "$pod" -- psql -U "$user" -d "$db" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)
  [ "$count" = "0" ] || { echo "FAIL: $db has $count user tables (expected 0)"; exit 1; }
done

echo "PASS: E4 — 3 postgres ready, all DBs empty"
