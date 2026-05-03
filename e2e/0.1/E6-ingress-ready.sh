#!/usr/bin/env bash
set -euo pipefail
kubectl -n kacho wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx --timeout=180s
# 503 — это OK: api-gateway ещё не задеплоен
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://api.kacho.local/ -H 'Host: api.kacho.local' || echo "000")
case "$CODE" in
  503|404) echo "PASS: E6 — ingress responded with $CODE (api-gateway not deployed yet)";;
  *) echo "FAIL: E6 — unexpected code $CODE"; exit 1;;
esac
