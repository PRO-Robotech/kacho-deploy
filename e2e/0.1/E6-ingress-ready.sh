#!/usr/bin/env bash
set -euo pipefail
kubectl -n kacho wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s

# Используем --resolve чтобы не зависеть от /etc/hosts
# 503 (api-gateway не задеплоен) или 404 — это OK
CODE=$(curl -s -o /dev/null -w '%{http_code}' --resolve api.kacho.local:80:127.0.0.1 http://api.kacho.local/ -H 'Host: api.kacho.local' || echo "000")
case "$CODE" in
  503|404) echo "PASS: E6 — ingress responded with $CODE (api-gateway not deployed yet — expected)";;
  *) echo "FAIL: E6 — unexpected code $CODE"; exit 1;;
esac
