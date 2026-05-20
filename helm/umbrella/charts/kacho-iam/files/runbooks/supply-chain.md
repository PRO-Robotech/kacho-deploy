# Runbook — Supply-chain build + sign + attest

**Audience**: each kacho-* service repo CI maintainer.
**Phase**: 11 (KAC-127).
**Last reviewed**: 2026-05-19.

This runbook documents the **mandatory CI pipeline** every kacho-* service
must implement in `.github/workflows/release-<svc>.yml`. It is enforced at
deploy-time by the `cosign-policy-controller` (Phase 10) — unsigned/unattested
images **will be rejected** at admission.

## Required CI stages

```text
┌─────────────────────────────────────────────────────────────────────┐
│  build → SBOM → SLSA-provenance → cosign-sign → push → verify       │
└─────────────────────────────────────────────────────────────────────┘
```

### 1. Build (reproducible)

Use `ko` for Go services or `goreleaser` for multi-arch:

```yaml
- name: Build container
  uses: ko-build/setup-ko@v0.7
- name: Build + push
  run: |
    export KO_DOCKER_REPO=ghcr.io/pro-robotech/kacho-<svc>
    ko build --bare --tags ${{ github.sha }},${{ github.ref_name }} \
      ./cmd/<svc>
```

Reproducibility check: `cosign verify-blob --certificate <cert> <image>` —
SHA should match for the same source.

### 2. SBOM via syft

```yaml
- name: Install syft
  uses: anchore/sbom-action/download-syft@v0.17
- name: Generate SBOM (SPDX)
  run: syft ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }} \
            -o spdx-json > sbom.spdx.json
- name: Generate SBOM (CycloneDX)
  run: syft ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }} \
            -o cyclonedx-json > sbom.cyclonedx.json
- name: Attach SBOM to image
  run: cosign attach sbom \
        --sbom sbom.spdx.json --type spdx \
        ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }}
```

### 3. SLSA L3 provenance via in-toto

```yaml
- name: SLSA provenance attestation
  uses: actions/attest-build-provenance@v2
  with:
    subject-name: ghcr.io/pro-robotech/kacho-<svc>
    subject-digest: ${{ steps.build.outputs.digest }}
    push-to-registry: true
```

### 4. cosign sign

**Non-prod** (dev/staging): keyless via Sigstore Fulcio (GitHub Actions OIDC).

```yaml
- name: Cosign sign (keyless)
  if: github.ref != 'refs/heads/main'
  run: |
    cosign sign --yes \
      --identity-token "$(curl -sLS \
        ${ACTIONS_ID_TOKEN_REQUEST_URL}\&audience=sigstore \
        -H \"Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN\" | jq -r .value)" \
      ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }}
```

**Prod** (main branch): offline key from kacho-platform-team:

```yaml
- name: Cosign sign (offline key)
  if: github.ref == 'refs/heads/main'
  env:
    COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
  run: |
    echo "${{ secrets.COSIGN_PRIVATE_KEY }}" > /tmp/cosign.key
    cosign sign --key /tmp/cosign.key --yes \
      ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }}
    rm -f /tmp/cosign.key
```

### 5. Vulnerability scan gate

```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@0.24
  with:
    image-ref: ghcr.io/pro-robotech/kacho-<svc>:${{ github.sha }}
    severity: HIGH,CRITICAL
    exit-code: 1                    # fail build on HIGH/CRITICAL
    ignore-unfixed: false

- name: gosec
  run: gosec -severity=high -fmt=sarif -out=gosec.sarif ./...
```

### 6. Verify after deploy

Argo CD sync hook + SPIRE Cosign attestor (Phase 10) re-verify at every
deploy. Manual check:

```
cosign verify --key https://kacho-platform.cloud/cosign.pub \
  ghcr.io/pro-robotech/kacho-<svc>:<sha>
```

## Banned licenses (backend)

Renovate config rejects any direct dep with: GPLv3, AGPL, SSPL, Commons
Clause. Allowed: MIT, Apache-2.0, BSD-2/3, MPL-2.0, ISC, Unlicense.

## Verification commands (one-liners)

```
make sbom-verify        # decodes SBOM attestation, prints package list
make slsa-verify-image  # validates SLSA L3 attestation
make cosign-verify      # validates cosign signature against trusted key
```

## Failure modes

* **Build hash differs** → reproducibility broken; investigate floating deps.
* **SBOM missing package** → syft scan flag wrong; check `--scope`.
* **SLSA attestation missing** → workflow forgot `attest-build-provenance` step.
* **cosign sign failed** → check OIDC token / private key secret.
* **Trivy fails on CVE** → patch dep OR open `wontfix` issue with explicit
  remediation SLA before merge.

## Cross-references

* `cosign-policy-controller` chart — enforces signed-only at admission
  (Phase 10).
* `argocd-sync-failure.md` — when verify fails at deploy.
