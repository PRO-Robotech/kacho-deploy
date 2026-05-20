# NIST Cybersecurity Framework 2.0 — Function Mapping

**Framework**: NIST CSF 2.0 (released February 2024)
**Date**: 2026-05-20
**Status**: SELF-ASSESSED PASS

> NIST CSF 2.0 organizes cybersecurity into 6 Functions: **Govern, Identify,
> Protect, Detect, Respond, Recover**. Govern is new in 2.0 (was implicit
> in 1.1). Each Function has Categories and Subcategories.

## GV — Govern (new in CSF 2.0)

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| GV.OC | Organizational Context | Platform vision in `docs/specs/00-overview-and-scope.md` |
| GV.RM | Risk Management Strategy | STRIDE threat model + ASVS L3 + risk-register `docs/security/risk-register.md` |
| GV.RR | Roles, Responsibilities, and Authorities | CODEOWNERS + KAC `агент` field + RACI in `docs/team/raci.md` |
| GV.PO | Policy | `docs/security/` policy folder; quarterly review |
| GV.OV | Oversight | Platform Lead approves arch changes; security review per acceptance |
| GV.SC | Cybersecurity Supply Chain Risk Management | SBOM (Phase 11) + cosign + trivy on transitive deps |

## ID — Identify

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| ID.AM | Asset Management | SBOM per image (syft Phase 11); k8s resource inventory; cloud asset inventory |
| ID.RA | Risk Assessment | STRIDE threat model `threat-model.md` |
| ID.IM | Improvement | Post-mortems for SEV-1/2; chaos gameday learnings |

## PR — Protect

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| PR.AA | Identity Management, Authentication, and Access Control | IAM (Phase 1-6); OpenFGA (Phase 3); Passkey + DPoP (Phase 2) |
| PR.AT | Awareness and Training | Annual security training; phishing simulations; documented in HR |
| PR.DS | Data Security | Postgres TDE + KMS-CMK; mTLS Phase 10; HSM Phase 11 |
| PR.PS | Platform Security | Cosign policy (Phase 11) + admission strict (Phase 12); PodSecurityStandard `restricted` |
| PR.IR | Technology Infrastructure Resilience | Multi-region active-active (Phase 11); Patroni HA Postgres |

## DE — Detect

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| DE.CM | Continuous Monitoring | VictoriaMetrics + Grafana; AlertManager → PagerDuty |
| DE.AE | Adverse Event Analysis | Audit pipeline (Phase 9) + SIEM via Kafka Connect; anomaly detection on ClickHouse |

## RS — Respond

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| RS.MA | Incident Management | Runbooks `helm/umbrella/charts/litmus-chaos/files/runbooks/` |
| RS.AN | Incident Analysis | Audit pipeline forensics — Kafka events with Merkle chain |
| RS.CO | Incident Response Reporting and Communication | security.txt + responsible-disclosure policy + customer-comm templates |
| RS.MI | Incident Mitigation | Break-glass 2-approve + JIT/PIM (Phase 7); rapid-revoke flows |

## RC — Recover

| Category | Subcategory | Kachō Implementation |
|----------|-------------|----------------------|
| RC.RP | Incident Recovery Plan Execution | DR plan + BCP + multi-region failover (Phase 11) |
| RC.CO | Incident Recovery Communication | Status page + customer-notification templates |

---

## Implementation Tier (CSF 2.0 §3.3)

Kachō Cloud is at **Tier 3 — Repeatable**:
- Risk management practices formally approved and expressed as policy.
- Risk-informed practices integrated into the organization's culture.
- Organization-wide approach to managing cybersecurity risk.
- Information is shared with external partners as appropriate.

**Tier 4 — Adaptive** is the goal post-GA (12-18 months):
- Adapts cybersecurity practices based on previous and current cybersecurity activities including lessons learned.
- Incorporates advanced cybersecurity technologies and practices.
- Active sharing of information with broader community.

## Profile (CSF 2.0 §3.4)

**Current profile** documented above (Tier 3).

**Target profile**:
- All Tier 4 attributes met.
- ISO 27001 cert achieved.
- SOC 2 Type II report issued.
- Bug bounty program operational (HackerOne).
- Pentest annual + on-major-release.

**Gap analysis** identifies the following work-streams to reach Target:
1. Tier 4 information-sharing — engage with FS-ISAC / Cloud-Security-Alliance.
2. SOC 2 Type II — engage auditor (User-action).
3. ISO 27001 — engage cert body (User-action).
4. HackerOne — engagement (User-action).
5. Annual pentest cycle — Phase 12 prep done; execute (User-action).

## References

- NIST CSF 2.0: https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.29.pdf
- NIST CSF 2.0 Implementation Examples: https://csrc.nist.gov/publications/detail/csrc-conference-paper/2024/
- Companion ISO 27001 mapping: `iso27001-2022-mapping.md`
- Companion SOC 2 mapping: `soc2-type2-mapping.md`
