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

# Каждая БД доступна; migrations applied (count > 0).
# After KAC-94 schema rename vpc lives in `kacho_vpc` schema, not `public`.
declare -A DBS=(
  [kacho-umbrella-pg-resource-manager-0]="resource_manager kacho_resource_manager"
  [kacho-umbrella-pg-vpc-0]="vpc kacho_vpc"
  [kacho-umbrella-pg-compute-0]="compute kacho_compute"
)
for pod in "${!DBS[@]}"; do
  read -r user db <<< "${DBS[$pod]}"
  count=""
  # migrations runs из app-side init-container; pg pod ready != tables applied,
  # дай до 60s на migrations завершиться.
  for attempt in $(seq 1 12); do
    # `set -euo pipefail` + non-zero kubectl exit убил бы script досрочно —
    # explicit `|| echo ERR` гасит non-zero exit и сохраняет stderr.
    out=$(kubectl -n kacho exec "$pod" -- psql -U "$user" -d "$db" -tAXqc \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')" 2>&1 \
      || echo "ERR")
    count=$(printf '%s' "$out" | tr -d '[:space:]')
    if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]; then
      echo "  $db: $count tables (attempt $attempt)"
      break
    fi
    echo "  $db: out=[$out] attempt $attempt — retrying..."
    sleep 5
    count=""
  done
  [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] || {
    echo "FAIL: $db has count=[$count] (expected > 0 after migrations, waited 60s)"
    exit 1
  }
done

echo "PASS: E4 — 3 postgres ready, migrations applied"
