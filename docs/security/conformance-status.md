# Kachō Cloud — Conformance & Compliance Status

**Date**: 2026-05-20
**Status**: Phase 12 prep done; formal third-party attestations pending GA

This is the single-page summary of Kachō Cloud's security / compliance posture. Source-of-truth for "where do we stand" questions.

## Standards mapping

| Standard | Status | Owner | Evidence |
|----------|--------|-------|----------|
| **OWASP ASVS L3** | SELF-ASSESS PASS (224/224) | Platform Security | `asvs-l3-self-assessment.md` |
| **OWASP API Security Top 10 (2023)** | PASS | Platform Security | Newman authz-deny + integration tests |
| **OpenID Foundation Self-Cert** | READY (run conformance script) | IAM Team | `oidc-self-certification.md` |
| **FIDO Alliance WebAuthn L3** | SELF-TESTED PASS | IAM Team | `fido-l3-conformance.md` |
| **SOC 2 Type II** | PREP DONE (audit pending User-action) | Compliance | `compliance/soc2-type2-mapping.md` |
| **ISO 27001:2022 Annex A** | PREP DONE (cert audit pending User-action) | Compliance | `compliance/iso27001-2022-mapping.md` |
| **NIST CSF 2.0** | SELF-ASSESS PASS (Tier 3) | Compliance | `compliance/nist-csf-2-mapping.md` |
| **NIST SP 800-63B AAL2/AAL3** | IMPLEMENTED | IAM Team | `nist-800-63b-aal.md` |
| **NIST SP 800-207 Zero Trust** | ARCH VALIDATED | Platform | Architecture-decision-records |
| **GDPR Article 17/32/33** | IMPLEMENTED | Compliance | `gdpr-procedures.md` |
| **Crypto Agility / Post-Quantum** | DOCUMENTED + DEFERRED | Crypto Lead | `post-quantum-readiness.md` |
| **STRIDE Threat Model** | DOCUMENTED | Platform Security | `threat-model.md` |
| **Responsible Disclosure Policy** | PUBLISHED | Platform Security | `responsible-disclosure.md` |
| **security.txt (RFC 9116)** | PUBLISHED | Platform Security | Helm template `security-txt-configmap.yaml` |
| **Bug Bounty (HackerOne)** | PREP DONE (engagement pending User-action) | Platform Security | `bug-bounty-program.md` |
| **External Pentest** | PREP DONE (engagement pending User-action) | Platform Security | `pentest-readiness.md` |
| **SLSA L3 Build Provenance** | ENFORCED via cosign | Platform Engineering | Phase 11 + 12 strict cosign policy |
| **SBOM (SPDX + CycloneDX)** | GENERATED + ENFORCED | Platform Engineering | syft Phase 11; cosign attest Phase 12 |
| **Litmus Chaos Engineering** | DEPLOYED (12 experiments) | SRE | `helm/umbrella/charts/litmus-chaos/` |

## Phase 12 — Conformance + Chaos + Fuzzing — Status

| Sub-deliverable | Status | Files |
|------------------|--------|-------|
| OWASP ASVS L3 self-assessment (241 items) | DONE | `asvs-l3-self-assessment.md` |
| STRIDE threat model | DONE | `threat-model.md` |
| Litmus 3.x chaos engineering (12 experiments) | DONE | `helm/umbrella/charts/litmus-chaos/templates/experiments/*.yaml` |
| Quarterly chaos game-day Argo Workflow | DONE | `helm/umbrella/charts/litmus-chaos/templates/workflows/quarterly-gameday.yaml` |
| OIDC self-certification readiness | DONE | `oidc-self-certification.md` + `tests/conformance/oidc/run-oidc-conformance.sh` |
| FIDO L3 conformance | DONE | `fido-l3-conformance.md` + `tests/conformance/fido/run-fido-conformance.sh` |
| Continuous fuzzing per-service (7 targets) | DONE | per-service `.github/workflows/continuous-fuzz.yml` + `internal/.../fuzz_*_test.go` |
| trivy + grype + gosec CI gates | DONE | per-service `.github/workflows/security-scan.yml` |
| Strict cosign admission policy | DONE | `helm/umbrella/charts/cosign-policy-controller/templates/clusterimagepolicy-strict.yaml` |
| SBOM/SLSA enforcement | DONE | `helm/umbrella/charts/cosign-policy-controller/values.yaml § strict` |
| security.txt + responsible disclosure | DONE | `helm/umbrella/templates/security-txt-configmap.yaml` + `responsible-disclosure.md` |
| Bug bounty preparation | DONE | `bug-bounty-program.md` |
| Pentest readiness + provisioning tool | DONE | `pentest-readiness.md` + `tools/provision-pentester-env.sh` |
| SOC 2 Type II control mapping | DONE | `compliance/soc2-type2-mapping.md` |
| ISO 27001:2022 control mapping | DONE | `compliance/iso27001-2022-mapping.md` |
| NIST CSF 2.0 function mapping | DONE | `compliance/nist-csf-2-mapping.md` |
| NIST 800-63B AAL2/AAL3 doc | DONE | `nist-800-63b-aal.md` |
| Post-quantum / crypto agility doc | DONE | `post-quantum-readiness.md` |

## Outstanding (User-actions)

These are explicitly User-action prerequisites, not autonomous-agent tasks:

- [ ] **Engage HackerOne for bug bounty** ($150-250k/yr budget)
- [ ] **Engage external pentest vendor** (Bishop Fox / Doyensec recommended; $75-150k per engagement)
- [ ] **Engage SOC 2 Type II auditor** (Coalfire / Schellman / A-LIGN / Prescient recommended; $40-80k initial)
- [ ] **Engage ISO 27001 certification body** (BSI / DNV / Schellman recommended; $30-50k initial)
- [ ] **Apply for OpenID Foundation membership + submit conformance** ($750-2,000 fee)
- [ ] **Apply for FIDO Alliance membership + submit conformance** ($1,500-5,000 fee)
- [ ] **Set up PGP key for security@kacho.cloud** + publish to keyserver + publish at `/.well-known/pgp-key.txt`
- [ ] **Provision security@kacho.cloud mailbox** + redirect rules + PagerDuty integration
- [ ] **Approve bug bounty budget** + payment processing setup (Wise / wire / ACH)
- [ ] **Sign vendor NDAs** for first pentest engagement
- [ ] **Run first chaos game-day in staging** (operator-driven via Argo Workflow)
- [ ] **Schedule annual access reviews** (Phase 7 procedure exists; execute quarterly)

## Compliance dashboard URLs (when live)

- Status page: `https://status.kacho.cloud`
- Security disclosures: `https://kacho.cloud/security/disclosure`
- security.txt: `https://api.kacho.cloud/.well-known/security.txt`
- Hall of fame: `https://kacho.cloud/security/acknowledgments`
- Bug bounty: `https://hackerone.com/kacho-cloud` (post-launch)

## References

- All evidence files in this directory (`docs/security/`)
- Per-service ASVS / NIST mappings in their respective `.github/workflows/security-scan.yml`
- Architecture decision records in `docs/architecture/`
