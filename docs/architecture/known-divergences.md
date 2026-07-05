# kacho-deploy — known divergences (by-design)

Deliberate, reviewed departures from a naive default. Not bugs, not tech-debt —
each entry states the decision, the rationale, and the guardrail that keeps it
honest. Add here instead of opening an issue when a choice is intentional.

## 1. api-gateway public ingress is umbrella-owned, backends the `tls` listener

**Decision.** The umbrella renders its own `templates/api-gateway-ingress.yaml`
for the public api-gateway ingress and disables the api-gateway **sub-chart's**
ingress via `api-gateway.ingress.enabled=false` (`helm/umbrella/values.yaml`).
The umbrella ingress backends the api-gateway pod's **`tls`** Service port
(:8443) with `nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"`.

**Why (security — ban #6 / defense-in-depth).** The api-gateway pod runs two
HTTP surfaces behind cmux:

- the plaintext **`cmux`** listener (:8080) — the *cluster-internal* surface. It
  is **not** wrapped by `listenerorigin.ExternalListener`, so the REST dispatcher
  never tags requests arriving there as external-origin and **serves Internal\***
  **REST** (AddressPool, Region/Zone admin, InternalAuthzCache, …). This is
  intentional for in-cluster UI / admin / port-forward, which dial the ClusterIP
  `cmux` port directly.
- the **`tls`** listener (:8443) — wrapped by `listenerorigin.ExternalListener`
  in `cmd/api-gateway/main.go`. Requests arriving here are tagged external-origin
  and the REST dispatcher returns **404 for every Internal\*** path — the exact
  behaviour the api-gateway external-isolation fix introduced.

The api-gateway sub-chart's *default* ingress points at `cmux` (its release-time
default). Routed through the public ingress, that would publish Internal\* REST on
the external edge — violating ban #6 ("`Internal.*` methods не публикуются на
external endpoint"). The public edge **must** traverse the external-marked `tls`
listener so the external-404 gate is live rather than dead code. In-cluster
consumers keep reaching Internal\* on the `cmux` ClusterIP port unchanged.

**Why umbrella-owned rather than a sub-chart values override.** The sub-chart
ingress template hard-codes `backend.service.port.name: cmux` with no value hook
to retarget it, and the sub-chart is vendored from the sibling `kacho-api-gateway`
repo (gitignored `helm/umbrella/charts/api-gateway/` + `*.tgz`), so it cannot be
edited from this repo. Disabling it and rendering an umbrella-owned ingress keeps
the fix entirely within `kacho-deploy`'s git-tracked files, verifiable by
`helm template` / `helm lint`. `host`, `tls.secretName` and `proxyReadTimeout`
are still inherited from the api-gateway sub-chart values (parent reads
`.Values."api-gateway".*`), so per-cluster overlays that set the ingress host keep
working.

**Follow-up (sibling repo, out of scope here).** The api-gateway sub-chart's own
default ingress (`kacho-api-gateway/deploy/templates/ingress.yaml`) still backends
`cmux`; it is only harmless because the umbrella disables it. A sibling-repo
change to backend the `tls` port (so a *standalone* api-gateway install is also
safe) should be tracked as a `kacho-api-gateway` issue.

**Guardrails.**
- `tests/helm/jobs-cronjobs-hardening-test.sh` §5 asserts exactly one Ingress
  named `api-gateway` renders, with `backend.service.port.name == tls` and
  `backend-protocol == GRPCS` (fails on any regression to `cmux`/`GRPC`).
- The umbrella ingress template `fail`s the render if
  `apiGatewayIngress.enabled=true` while `api-gateway.tls.enabled=false` (no
  external-marked TLS listener to route to) — no silent fallback to the insecure
  `cmux` path.

## 2. Auxiliary Jobs / CronJobs carry the same restricted PSS floor as Deployments

**Decision.** Every umbrella-owned pod-bearing workload — not only the
long-running Deployments — enforces the restricted Pod Security Standards floor
(`runAsNonRoot`, `runAsUser` non-zero, `allowPrivilegeEscalation:false`,
`readOnlyRootFilesystem:true`, `capabilities.drop:[ALL]`,
`seccompProfile:RuntimeDefault`). This includes the `openfga-bootstrap` and
`openfga-postgres-init` hook Jobs, the `kacho-iam` `jwks-rotator` CronJob, and the
`kacho-geo` `data-migration` Job. A writable `emptyDir` is mounted at `/tmp`
(`HOME=/tmp`) so the read-only rootfs does not break kubectl discovery cache /
psql history.

**Why.** These Jobs hold real blast-radius credentials — the bootstrap Job's
ServiceAccount can create Secrets and patch Deployments namespace-wide; the
jwks-rotator injects the JWKS AES encryption key + DB password; the postgres-init
Job carries Postgres admin creds. A root, writable-rootfs, full-capability
container maximises the damage from a compromised image or script. The restricted
floor contains it identically to the serve pods (CIS Kubernetes 5.2 / CWE-250).

**Guardrails.**
- `tests/helm/jobs-cronjobs-hardening-test.sh` §1–4 asserts the pod- and
  container-level floor on all four workloads.
- The CI Trivy IaC gate (`.github/workflows/ci.yaml`, `helm-lint` job) now
  enumerates **all** kacho-owned Job/CronJob/Deployment templates (r2 only
  covered the Deployments + two hook Jobs), so a future hardening regression on
  any of them fails the build.
