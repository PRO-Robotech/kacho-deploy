# SPIRE Registration Entries (Phase 10 KAC-127)

Declarative SPIFFE registration manifests for Kachō services. In Phase 10 these
entries are applied via post-install Job in `spire-server` Helm chart; in Phase
11 Argo CD reconciler watches this directory and pushes to
`InternalSpiffeRegistrationService.Upsert` in kacho-iam (P10-D8 / P10-D22).

## Files

- `kacho-iam.yaml` — kacho-iam service SPIFFE-ID + selectors
- `kacho-vpc.yaml` — kacho-vpc service
- `kacho-compute.yaml` — kacho-compute service
- `kacho-loadbalancer.yaml` — kacho-loadbalancer service
- `kacho-api-gateway.yaml` — kacho-api-gateway service
- `kacho-ui-admin.yaml` — UI admin pod
- `kacho-vpc-implement.yaml` — data-plane controller
- `cosign-attestor-config.yaml` — cosign trusted signers config

## Format

Each manifest declares:

```yaml
apiVersion: kacho.cloud/v1
kind: SpiffeRegistration
metadata:
  name: kacho-<svc>
spec:
  spiffeId: spiffe://{{ trustDomain }}/ns/kacho-system/sa/kacho-<svc>
  parentId: spiffe://{{ trustDomain }}/ns/spire-system/sa/spire-agent
  selectors:
    - type: k8s
      value: ns:kacho-system
    - type: k8s
      value: sa:kacho-<svc>
    - type: cosign
      value: image-signature:<fingerprint>
  ttl: 3600
```

## Trust domain — configurable

`{{ trustDomain }}` is replaced at deploy time via Helm value `spiffe.trustDomain`:

- dev: `kacho.dev.cloud`
- staging: `kacho.staging.cloud`
- prod: `kacho.cloud`
