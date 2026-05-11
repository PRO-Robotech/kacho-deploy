#!/usr/bin/env bash
# kacho-deploy/ci/seed.sh — seed fixtures into the CI compose stack and emit the
# resulting resource IDs so the newman suite can pick them up.
#
# What the newman env file (kacho-vpc/tests/newman/environments/local.postman_environment.json)
# expects to already exist:
#   existingOrgId        — an Organization (resource-manager auto-bootstraps "default")
#   existingCloudId      — a Cloud under it (auto-bootstrapped "default")
#   existingFolderId     — a Folder under it (auto-bootstrapped "default")
#   existingFolderCrossId— a SECOND folder, for cross-folder Move tests (we create it)
#   existingZoneId       — "ru-central1-a" (we create region ru-central1 + zones a..d)
#   existingZoneAltId    — "ru-central1-b"
#   + a default EXTERNAL_PUBLIC AddressPool on ru-central1-a (for external-IP allocate)
#
# resource-manager's bootstrap.EnsureDefaults creates the default Org→Cloud→Folder
# with RANDOM ids, so we discover them via the REST API rather than hardcoding.
#
# Output: writes `KEY=value` lines to $OUT (default: ci/.seeded-ids.env). The CI
# job sources it and passes the ids to newman via `run.sh --env-var KEY=value`.
#
# Usage: BASE_URL=http://localhost:28080 OUT=ci/.seeded-ids.env ./ci/seed.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:28080}"
OUT="${OUT:-$(dirname "$0")/.seeded-ids.env}"
REGION_ID="ru-central1"
ZONES=(ru-central1-a ru-central1-b ru-central1-c ru-central1-d)

req() {
  # req METHOD PATH [JSON-BODY] -> prints response body, fails on curl error
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "$BASE_URL$path" -H 'Content-Type: application/json' -d "$body"
  else
    curl -fsS -X "$method" "$BASE_URL$path"
  fi
}

# tolerant request: never fails the script; prints body (possibly an error JSON)
treq() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$BASE_URL$path" -H 'Content-Type: application/json' -d "$body" || true
  else
    curl -sS -X "$method" "$BASE_URL$path" || true
  fi
}

echo "[seed] waiting for api-gateway at $BASE_URL ..."
for i in $(seq 1 60); do
  if curl -fsS "$BASE_URL/healthz" >/dev/null 2>&1; then break; fi
  sleep 2
  if [[ "$i" == 60 ]]; then echo "[seed] FATAL: api-gateway never became healthy"; exit 1; fi
done

# resource-manager bootstrap is async-on-start; wait until the default Org/Cloud/Folder
# chain is queryable through the gateway.
echo "[seed] waiting for resource-manager default Organization/Cloud/Folder ..."
ORG_ID="" CLOUD_ID="" FOLDER_ID=""
for i in $(seq 1 60); do
  ORG_ID=$(treq GET "/organization-manager/v1/organizations" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print((d.get("organizations") or [{}])[0].get("id",""))
except Exception: print("")' )
  if [[ -n "$ORG_ID" ]]; then
    CLOUD_ID=$(treq GET "/resource-manager/v1/clouds?organizationId=$ORG_ID" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print((d.get("clouds") or [{}])[0].get("id",""))
except Exception: print("")' )
  fi
  if [[ -n "$CLOUD_ID" ]]; then
    FOLDER_ID=$(treq GET "/resource-manager/v1/folders?cloudId=$CLOUD_ID" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print((d.get("folders") or [{}])[0].get("id",""))
except Exception: print("")' )
  fi
  if [[ -n "$ORG_ID" && -n "$CLOUD_ID" && -n "$FOLDER_ID" ]]; then break; fi
  sleep 2
  if [[ "$i" == 60 ]]; then echo "[seed] FATAL: default Org/Cloud/Folder never appeared (org=$ORG_ID cloud=$CLOUD_ID folder=$FOLDER_ID)"; exit 1; fi
done
echo "[seed] org=$ORG_ID cloud=$CLOUD_ID folder=$FOLDER_ID"

# --- second folder for cross-folder Move tests (Folder.Create returns an Operation) ---
echo "[seed] creating cross-folder ..."
CROSS_FOLDER_ID=""
# Reuse if a previous run left it (idempotent CI re-runs against a kept stack).
CROSS_FOLDER_ID=$(treq GET "/resource-manager/v1/folders?cloudId=$CLOUD_ID" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin)
  for f in d.get("folders") or []:
    if f.get("name")=="newman-cross": print(f.get("id","")); break
except Exception: pass')
if [[ -z "$CROSS_FOLDER_ID" ]]; then
  CREATE_RESP=$(req POST "/resource-manager/v1/folders" "{\"cloudId\":\"$CLOUD_ID\",\"name\":\"newman-cross\",\"description\":\"newman cross-folder fixture\"}")
  OP_ID=$(printf '%s' "$CREATE_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
  for i in $(seq 1 30); do
    OP=$(treq GET "/operations/$OP_ID")
    DONE=$(printf '%s' "$OP" | python3 -c 'import sys,json;
try: print("1" if json.load(sys.stdin).get("done") else "")
except Exception: print("")')
    if [[ -n "$DONE" ]]; then
      CROSS_FOLDER_ID=$(printf '%s' "$OP" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print((d.get("metadata") or {}).get("folderId",""))
except Exception: print("")')
      break
    fi
    sleep 1
  done
fi
[[ -n "$CROSS_FOLDER_ID" ]] || { echo "[seed] FATAL: cross-folder not created"; exit 1; }
echo "[seed] cross-folder=$CROSS_FOLDER_ID"

# --- Region ru-central1 + zones ru-central1-{a,b,c,d} (idempotent: ignore AlreadyExists) ---
echo "[seed] creating region $REGION_ID ..."
treq POST "/vpc/v1/regions" "{\"id\":\"$REGION_ID\",\"name\":\"Russia Central 1\"}" >/dev/null
for z in "${ZONES[@]}"; do
  echo "[seed] creating zone $z ..."
  treq POST "/vpc/v1/zones" "{\"id\":\"$z\",\"regionId\":\"$REGION_ID\",\"name\":\"$z\"}" >/dev/null
done

# --- default EXTERNAL_PUBLIC AddressPool on ru-central1-a (for external-IP allocate) ---
# Only create if there isn't already a default EXTERNAL_PUBLIC pool on that zone
# (partial unique index WHERE is_default forbids a second one).
echo "[seed] ensuring default EXTERNAL_PUBLIC AddressPool on ru-central1-a ..."
HAS_DEFAULT=$(treq GET "/vpc/v1/addressPools?zoneId=ru-central1-a&kind=EXTERNAL_PUBLIC" | python3 -c 'import sys,json;
try:
  d=json.load(sys.stdin); print("1" if any(p.get("isDefault") for p in (d.get("pools") or [])) else "")
except Exception: print("")')
if [[ -z "$HAS_DEFAULT" ]]; then
  treq POST "/vpc/v1/addressPools" '{"name":"default-ru-central1-a","kind":"EXTERNAL_PUBLIC","zoneId":"ru-central1-a","cidrBlocks":["198.51.100.0/24"],"isDefault":true}' >/dev/null
fi

# --- emit ids ---
cat > "$OUT" <<EOF
existingOrgId=$ORG_ID
existingCloudId=$CLOUD_ID
existingFolderId=$FOLDER_ID
existingFolderCrossId=$CROSS_FOLDER_ID
existingZoneId=ru-central1-a
existingZoneAltId=ru-central1-b
EOF
echo "[seed] wrote $OUT:"
cat "$OUT"
