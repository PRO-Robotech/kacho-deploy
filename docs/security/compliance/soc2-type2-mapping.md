# SOC 2 Type II — Trust Services Criteria Mapping

**Framework**: AICPA Trust Services Criteria 2017 (revised 2022)
**Type**: Type II (operating effectiveness over time)
**Date**: 2026-05-20
**Status**: PREP DONE; auditor engagement is a User-action (NOT autonomous)

> SOC 2 Type II requires an independent auditor to attest that controls are
> designed and operating effectively over a 6-12 month period. This document
> maps each Common Criterion (CC) to the Kachō Cloud control implementation.
>
> **User-action prerequisite**: contract with AICPA-registered CPA firm
> specializing in SOC 2 (recommended: Coalfire, Schellman, A-LIGN, Prescient).
> Estimated cost $40k-$80k for first year. Typical timeline: 6-9 months from
> readiness assessment to report.

---

## CC1 — Control Environment

| Sub-criterion | Control | Implementation in Kachō |
|---------------|---------|-------------------------|
| CC1.1 | Demonstrate commitment to integrity and ethical values | Code of Conduct in `docs/legal/code-of-conduct.md`; CI runs gosec on every PR |
| CC1.2 | Demonstrate independence and board oversight | Architecture decision records (ADRs) require Platform Lead approval |
| CC1.3 | Establish structures, reporting lines, authorities | CODEOWNERS file + GitHub branch protection + KAC YouTrack workflow |
| CC1.4 | Demonstrate commitment to attract competent individuals | Onboarding checklist + security training docs |
| CC1.5 | Hold individuals accountable for internal control responsibilities | Audit pipeline (Phase 9) — every action attributed to principal |

---

## CC2 — Communication and Information

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC2.1 | Obtain or generate relevant, quality information | OpenTelemetry pipeline (Phase 11); Sloth SLO controller |
| CC2.2 | Communicate internally — objectives, responsibilities | Vault (`obsidian/kacho/`) + per-repo CLAUDE.md |
| CC2.3 | Communicate externally — vendors, customers | security.txt (Phase 12) + status page + customer portal |

---

## CC3 — Risk Assessment

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC3.1 | Specify objectives | OKR docs + acceptance specs `docs/specs/*.md` |
| CC3.2 | Identify risks | STRIDE threat model `docs/security/threat-model.md` |
| CC3.3 | Assess fraud risk | Audit pipeline anomaly detection; break-glass 2-approve |
| CC3.4 | Identify and assess significant change | Architecture decision records require security review; Phase-acceptance gates |

---

## CC4 — Monitoring Activities

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC4.1 | Select, develop, perform ongoing evaluations | VictoriaMetrics / Grafana dashboards; Sloth SLO; weekly review |
| CC4.2 | Evaluate and communicate deficiencies | KAC tickets in YouTrack `KAC` project + GitHub Issues per repo |

---

## CC5 — Control Activities

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC5.1 | Select and develop control activities that mitigate risks | OWASP ASVS L3 mappings (`asvs-l3-self-assessment.md`) |
| CC5.2 | Use technology in control activities | Cosign + SBOM + SLSA (Phase 11) + admission policy (Phase 12) |
| CC5.3 | Deploy policies and procedures | `docs/security/responsible-disclosure.md`; runbooks |

---

## CC6 — Logical and Physical Access Controls

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC6.1 | Implement logical access security controls | IAM (Phase 1-6) + OpenFGA RBAC + ABAC (Phase 3) |
| CC6.2 | Register and authorize users | Kratos selfservice + admin invite flow + ServiceAccount provisioning |
| CC6.3 | Authorize, modify, remove access | UI Account > Members; access-review job (Phase 7) |
| CC6.4 | Restrict physical access | Cloud-provider (AWS/GCP) SOC 2 inherited; on-prem N/A |
| CC6.5 | Discontinue logical / physical access for terminated users | Kratos identity-delete trigger; OIDC token-revocation; OpenFGA tuple-remove |
| CC6.6 | Implement logical access controls (protect from threats) | SPIRE + Cilium mesh (Phase 10); Phase 12 strict cosign |
| CC6.7 | Restrict transmission, movement, removal of information | TLS 1.3 + mTLS SPIFFE; egress NetworkPolicy + DLP |
| CC6.8 | Implement controls to prevent / detect / act upon unauthorized software | Cosign policy-controller (Phase 11/12 strict); trivy CI scan |

---

## CC7 — System Operations

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC7.1 | Detect, identify configuration changes | Argo CD GitOps (Phase 11); drift-detection alerts |
| CC7.2 | Monitor system components | Grafana + Mimir/Loki/Tempo dashboards |
| CC7.3 | Evaluate security events for impact | AlertManager → PagerDuty; SIEM via Kafka audit pipeline |
| CC7.4 | Respond to identified security events | Runbooks `helm/umbrella/charts/litmus-chaos/files/runbooks/` |
| CC7.5 | Recovery from identified security incidents | DR drill quarterly (Phase 12 chaos gameday) |

---

## CC8 — Change Management

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC8.1 | Authorize, design, develop, document changes | KAC ticket workflow (To do → In Progress → Test → Done) + PR reviews |

---

## CC9 — Risk Mitigation

| Sub-criterion | Control | Implementation |
|---------------|---------|----------------|
| CC9.1 | Identify, select, develop risk mitigation activities | STRIDE threat model + ASVS L3 (Phase 12) |
| CC9.2 | Vendor and business partner risk management | SBOM (Phase 11) — transitive dep visibility; trivy scan on PRs |

---

## Additional Trust Services Criteria

For "Security" only, CC1-CC9 are sufficient. For SOC 2 with Availability / Processing Integrity / Confidentiality / Privacy, additional criteria apply:

### A — Availability
- A1.1: Performance monitoring → Sloth SLO + AlertManager
- A1.2: Environmental safeguards → cloud-provider inherited
- A1.3: Recovery from incidents → DR drill (Phase 12 chaos gameday)

### PI — Processing Integrity
- PI1.1: Inputs validated → ASVS V5 (`asvs-l3-self-assessment.md`)
- PI1.2: Quality of outputs → integration tests + newman E2E

### C — Confidentiality
- C1.1: Identify and protect confidential information → data-classification + encryption-at-rest

### P — Privacy
- P1.1: Notice and consent → UI privacy policy / consent banner
- P4.1: Erasure (right-to-be-forgotten) → GDPR Article 17 flow (Phase 7)

---

## Audit readiness checklist

Before engaging auditor, verify:

- [ ] All 9 CC + selected Trust Services Criteria have documented control + evidence
- [ ] At least 6 months of operating evidence in audit pipeline (Kafka → ClickHouse)
- [ ] Asset inventory complete (SBOM via syft; image registry)
- [ ] Incident response runbooks tested via Litmus chaos gameday (Phase 12)
- [ ] Access reviews completed at least quarterly (Phase 7)
- [ ] Vendor risk assessments completed for top-N dependencies (renovate + trivy review)
- [ ] HR processes documented (onboarding / offboarding / training)
- [ ] Physical / environmental controls documented (cloud-provider inheritance memo)
- [ ] Vulnerability management — patch cadence + SLA per severity
- [ ] Penetration test report from current cycle (Phase 12 external pentest)
- [ ] Business continuity / DR plan tested

## References

- AICPA Trust Services Criteria 2017 (revised 2022): https://www.aicpa-cima.com/resources/landing/system-and-organization-controls-soc-suite-of-services
- AICPA SOC 2 Description Criteria
- NIST CSF 2.0 (parallel mapping): `nist-csf-2-mapping.md`
- ISO 27001:2022 (parallel mapping): `iso27001-2022-mapping.md`
