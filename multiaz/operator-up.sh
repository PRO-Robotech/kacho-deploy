#!/usr/bin/env bash
# multiaz/operator-up.sh — deploy the zone-aware kacho-vpc-operator (OP3-MULTIAZ)
# into a ZONAL kind cluster. The operator reads the CONTROL-PLANE kacho-vpc gRPC
# cross-cluster (NodePort on the control-plane node IP, public :9090 only — never
# :9091), materializes ONLY its own zone's subnets, and wires cross-zone L3 within
# a VPC (transit u2o subnet + cross-routes) + structural cross-VPC isolation.
#
# Usage: multiaz/operator-up.sh <ctx> <zone-id> <transit-host>
#   e.g. multiaz/operator-up.sh kind-kacho-zonea ru-central1-a 101
# Requires: control-plane ctx kind-kacho with svc kacho/vpc-cross (NodePort 30090),
# image kacho-vpc-operator:multiaz kind-loaded into <ctx>'s cluster.
set -euo pipefail

CTX="${1:?ctx}"; ZONE_ID="${2:?zone-id}"; TRANSIT_HOST="${3:?transit-host}"
CP_CTX="${CP_CTX:-kind-kacho}"
CP_NODE_IP="${CP_NODE_IP:-172.19.0.2}"
CP_NODEPORT="${CP_NODEPORT:-30090}"
# NB: do NOT use ${ZONES_JSON:-<default-with-braces>} — the }… in the default
# truncates at the first } (brace-expansion). Set explicitly when empty.
ZONES_JSON="${ZONES_JSON:-}"
if [ -z "$ZONES_JSON" ]; then
  ZONES_JSON='[{"id":"ru-central1-a","transitHost":101},{"id":"ru-central1-b","transitHost":151}]'
fi
NS=kacho-vpc-operator
OP_DIR="$(cd "$(dirname "$0")/../../kacho-vpc-operator" && pwd)"
IMG=kacho-vpc-operator:multiaz

case "$CTX" in kind-*) ;; *) echo "REFUSING non-kind ctx $CTX" >&2; exit 1;; esac

echo "--- [$CTX] namespace + CRDs + RBAC ---"
kubectl --context "$CTX" create ns "$NS" --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
kubectl --context "$CTX" apply -f "$OP_DIR/config/crd/bases/" >/dev/null
kubectl --context "$CTX" apply -f "$OP_DIR/config/rbac/role.yaml" >/dev/null
kubectl --context "$CTX" -n "$NS" create sa kacho-vpc-operator --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
# Full RBAC (helm-templated kacho-vpc-operator ClusterRole+Binding) — role.yaml only
# carries the kubebuilder manager-role subset (no namespaces/binding). Copy the
# working cluster-scoped RBAC from the control-plane.
for cr in kacho-vpc-operator kacho-project-operator; do
  kubectl --context "$CP_CTX" get clusterrole "$cr" -o yaml 2>/dev/null | sed '/resourceVersion:/d;/uid:/d;/creationTimestamp:/d' | kubectl --context "$CTX" apply -f - >/dev/null 2>&1 || true
  kubectl --context "$CP_CTX" get clusterrolebinding "$cr" -o yaml 2>/dev/null | sed '/resourceVersion:/d;/uid:/d;/creationTimestamp:/d' | kubectl --context "$CTX" apply -f - >/dev/null 2>&1 || true
done

echo "--- [$CTX] copy mTLS client-cert + identity from control-plane ---"
kubectl --context "$CP_CTX" -n "$NS" get secret vpc-operator-client-tls -o yaml \
  | sed '/resourceVersion:/d;/uid:/d;/creationTimestamp:/d;/ownerReferences:/,/uid:/d' \
  | kubectl --context "$CTX" apply -f - >/dev/null
kubectl --context "$CP_CTX" -n "$NS" get configmap kacho-vpc-operator-identity -o yaml \
  | sed '/resourceVersion:/d;/uid:/d;/creationTimestamp:/d' \
  | kubectl --context "$CTX" apply -f - >/dev/null

echo "--- [$CTX] webhook cert (self-signed + MutatingWebhookConfiguration) ---"
CTX="$CTX" bash "$OP_DIR/scripts/deploy-webhook.sh" >/dev/null 2>&1 || echo "  (webhook cert script: check separately)"

echo "--- [$CTX] deploy zone-aware operator (zone=$ZONE_ID transitHost=$TRANSIT_HOST) ---"
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: kacho-vpc-operator, namespace: $NS, labels: {app: kacho-vpc-operator}}
spec:
  replicas: 1
  selector: {matchLabels: {app: kacho-vpc-operator}}
  template:
    metadata: {labels: {app: kacho-vpc-operator}}
    spec:
      serviceAccountName: kacho-vpc-operator
      containers:
        - name: operator
          image: $IMG
          imagePullPolicy: IfNotPresent
          args: ["--enable-webhook=true","--webhook-port=9443","--webhook-cert-path=/tmp/k8s-webhook-server/serving-certs","--metrics-bind-address=0","--health-probe-bind-address=:8082","--resync-interval=10s"]
          env:
            - {name: KACHO_VPC_ADDR, value: "$CP_NODE_IP:$CP_NODEPORT"}
            - {name: KACHO_VPCOPERATOR_ZONE_ID, value: "$ZONE_ID"}
            - {name: KACHO_VPCOPERATOR_ZONES, value: '$ZONES_JSON'}
            - {name: KACHO_VPCOPERATOR_VPC_MTLS_ENABLE, value: "true"}
            - {name: KACHO_VPCOPERATOR_VPC_MTLS_CERTFILE, value: "/etc/kacho/operator-tls/tls.crt"}
            - {name: KACHO_VPCOPERATOR_VPC_MTLS_KEYFILE, value: "/etc/kacho/operator-tls/tls.key"}
            - {name: KACHO_VPCOPERATOR_VPC_MTLS_CAFILES, value: "/etc/kacho/operator-tls/ca.crt"}
            - {name: KACHO_VPCOPERATOR_VPC_MTLS_SERVERNAME, value: "vpc.kacho.svc.cluster.local"}
            - {name: KACHO_PRINCIPAL_TYPE, value: "service_account"}
            - name: KACHO_PRINCIPAL_ID
              valueFrom: {configMapKeyRef: {name: kacho-vpc-operator-identity, key: operatorSvaId}}
          ports: [{containerPort: 8082, name: health},{containerPort: 9443, name: webhook}]
          volumeMounts:
            - {name: webhook-cert, mountPath: /tmp/k8s-webhook-server/serving-certs, readOnly: true}
            - {name: operator-client-tls, mountPath: /etc/kacho/operator-tls, readOnly: true}
          readinessProbe: {httpGet: {path: /readyz, port: 8082}, initialDelaySeconds: 5}
      volumes:
        - {name: webhook-cert, secret: {secretName: kacho-vpc-operator-webhook-cert}}
        - {name: operator-client-tls, secret: {secretName: vpc-operator-client-tls}}
EOF
kubectl --context "$CTX" -n "$NS" rollout status deploy/kacho-vpc-operator --timeout=120s || true
echo "[$CTX] operator up (zone=$ZONE_ID)."
