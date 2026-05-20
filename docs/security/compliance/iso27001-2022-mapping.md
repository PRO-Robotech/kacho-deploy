# ISO 27001:2022 Annex A — Control Mapping

**Standard**: ISO/IEC 27001:2022 (Information Security Management Systems)
**Annex A**: 93 controls organized into 4 themes (A.5–A.8)
**Date**: 2026-05-20
**Status**: PREP DONE; certification audit is a User-action

> ISO 27001:2022 reduces the previous 114-control set (2013) to 93 controls,
> reorganized into 4 themes: Organizational, People, Physical, Technological.
> This document maps each control to Kachō Cloud implementation.
>
> **User-action prerequisite**: contract with accredited certification body
> (BSI, DNV, TÜV SÜD, SGS, Schellman). Estimated cost $30k-$50k for initial
> certification + $15k-$25k annual surveillance. Typical timeline: 9-12 months
> from gap assessment to certificate.

## Theme A.5 — Organizational Controls (37 controls)

| Control | Description | Kachō Implementation |
|---------|-------------|----------------------|
| A.5.1 | Policies for information security | `docs/security/` policy folder; reviewed quarterly |
| A.5.2 | Information security roles and responsibilities | CODEOWNERS + KAC `агент` field |
| A.5.3 | Segregation of duties | Branch-protection PR-approval ≠ author; break-glass 2-approve (Phase 7) |
| A.5.4 | Management responsibilities | Platform Lead approves architecture changes |
| A.5.5 | Contact with authorities | Incident response runbook lists data-protection authority contacts |
| A.5.6 | Contact with special interest groups | OWASP / FIRST / Cloud Security Alliance memberships (Q3 2026) |
| A.5.7 | Threat intelligence | trivy + grype CVE feed + dependabot security advisories |
| A.5.8 | Information security in project management | Phase-acceptance docs require security-section |
| A.5.9 | Inventory of information and other associated assets | SBOM (syft per image, Phase 11) + asset register |
| A.5.10 | Acceptable use of information and other associated assets | AUP doc in `docs/legal/aup.md` |
| A.5.11 | Return of assets | Offboarding checklist (HR doc) |
| A.5.12 | Classification of information | `kacho.io/data-class` label per resource (PII / Confidential / Internal / Public) |
| A.5.13 | Labelling of information | Resource-tag + audit-event class field |
| A.5.14 | Information transfer | TLS 1.3 + mTLS SPIFFE (Phase 10) for all transfers |
| A.5.15 | Access control | IAM (Phase 1-6); OpenFGA RBAC (Phase 3) |
| A.5.16 | Identity management | Kratos + kacho-iam (Phase 2 + 6) |
| A.5.17 | Authentication information | Passkey + DPoP (Phase 2); Argon2id for legacy |
| A.5.18 | Access rights | Per-RPC FGA Check (Phase 3); access reviews (Phase 7) |
| A.5.19 | Information security in supplier relationships | Vendor risk assessment process; SBOM for transitive deps |
| A.5.20 | Addressing information security within supplier agreements | DPA + supplier security questionnaire |
| A.5.21 | Managing information security in the ICT supply chain | Cosign signing (Phase 11) + admission policy strict (Phase 12) |
| A.5.22 | Monitoring, review and change management of supplier services | Renovate + dependabot daily; SLA review |
| A.5.23 | Information security for use of cloud services | Cloud-provider SOC 2 SoC reports collected; CSPM (Phase 13 planned) |
| A.5.24 | Information security incident management planning and preparation | Runbooks + Litmus chaos quarterly drill (Phase 12) |
| A.5.25 | Assessment and decision on information security events | AlertManager + PagerDuty + on-call rotation |
| A.5.26 | Response to information security incidents | Incident response process documented in runbooks |
| A.5.27 | Learning from information security incidents | Post-mortems required for SEV-1/2; tracked in `docs/security/incidents/` |
| A.5.28 | Collection of evidence | Audit pipeline (Phase 9) + Merkle batch hash; immutable Kafka log |
| A.5.29 | Information security during disruption | DR plan + BCP; chaos gameday tests resilience |
| A.5.30 | ICT readiness for business continuity | Multi-region active-active (Phase 11) + Patroni HA Postgres |
| A.5.31 | Identification of legal, statutory, regulatory and contractual requirements | Legal tracker `docs/legal/compliance-tracker.md` |
| A.5.32 | Intellectual property rights | License scan via syft + SBOM compliance check |
| A.5.33 | Protection of records | Audit log immutable + 7-year retention for regulated workloads |
| A.5.34 | Privacy and protection of PII | GDPR procedures `gdpr-procedures.md`; Article 32/17/33 implemented |
| A.5.35 | Independent review of information security | External pentest annual (Phase 12) + SOC 2 audit |
| A.5.36 | Compliance with policies, rules and standards for information security | ASVS L3 self-assessment + conformance status |
| A.5.37 | Documented operating procedures | Runbooks library in `helm/umbrella/charts/litmus-chaos/files/runbooks/` |

## Theme A.6 — People Controls (8 controls)

| Control | Description | Implementation |
|---------|-------------|----------------|
| A.6.1 | Screening | Background-check process for employees (HR) |
| A.6.2 | Terms and conditions of employment | Confidentiality clause in employment contract |
| A.6.3 | Information security awareness, education and training | Annual security training; phishing simulations |
| A.6.4 | Disciplinary process | HR policy (out of scope this repo) |
| A.6.5 | Responsibilities after termination or change of employment | Offboarding checklist incl. credential revocation |
| A.6.6 | Confidentiality or non-disclosure agreements | NDA signed by all employees + contractors |
| A.6.7 | Remote working | Remote work security policy (VPN + endpoint compliance) |
| A.6.8 | Information security event reporting | security@kacho.cloud channel + internal Slack #security |

## Theme A.7 — Physical Controls (14 controls)

Most physical controls inherited from cloud providers (AWS, GCP).

| Control | Description | Implementation |
|---------|-------------|----------------|
| A.7.1 | Physical security perimeter | Cloud-provider SOC 2 inherited |
| A.7.2 | Physical entry controls | Cloud-provider SOC 2 inherited |
| A.7.3 | Securing offices, rooms and facilities | Office security policy (HR) |
| A.7.4 | Physical security monitoring | Cloud-provider inherited |
| A.7.5 | Protecting against physical and environmental threats | Cloud-provider inherited |
| A.7.6 | Working in secure areas | Office policy |
| A.7.7 | Clear desk and clear screen | Office policy |
| A.7.8 | Equipment siting and protection | Cloud-provider inherited |
| A.7.9 | Security of assets off-premises | MDM on laptops; FileVault required |
| A.7.10 | Storage media | Encrypted storage required; secure disposal |
| A.7.11 | Supporting utilities | Cloud-provider inherited |
| A.7.12 | Cabling security | Cloud-provider inherited |
| A.7.13 | Equipment maintenance | Cloud-provider inherited |
| A.7.14 | Secure disposal or re-use of equipment | Secure-wipe policy + cryptographic erasure for PVs |

## Theme A.8 — Technological Controls (34 controls)

| Control | Description | Kachō Implementation |
|---------|-------------|----------------------|
| A.8.1 | User endpoint devices | MDM-enforced compliance baseline |
| A.8.2 | Privileged access rights | JIT/PIM (Phase 7) + break-glass 2-approve |
| A.8.3 | Information access restriction | OpenFGA per-resource Check (Phase 3) |
| A.8.4 | Access to source code | GitHub branch protection + CODEOWNERS |
| A.8.5 | Secure authentication | WebAuthn Passkey (Phase 2) + DPoP-bound tokens |
| A.8.6 | Capacity management | HPA + cluster autoscaler; capacity alerts |
| A.8.7 | Protection against malware | trivy / grype / gosec gates (Phase 12) |
| A.8.8 | Management of technical vulnerabilities | dependabot + Renovate + CVE-feed monitoring |
| A.8.9 | Configuration management | Helm + GitOps Argo CD (Phase 11) |
| A.8.10 | Information deletion | GDPR Article 17 erasure flow (Phase 7) |
| A.8.11 | Data masking | UI redacts sensitive fields; logs strip PII |
| A.8.12 | Data leakage prevention | Egress NetworkPolicy + DLP scan |
| A.8.13 | Information backup | Postgres WAL-G + S3 backup; daily verification |
| A.8.14 | Redundancy of information processing facilities | Multi-region active-active (Phase 11) |
| A.8.15 | Logging | OpenTelemetry + Loki + audit pipeline (Phase 9) |
| A.8.16 | Monitoring activities | VictoriaMetrics + Grafana + Sloth SLO |
| A.8.17 | Clock synchronization | chronyd / kubelet NTP |
| A.8.18 | Use of privileged utility programs | Break-glass 2-approve required |
| A.8.19 | Installation of software on operational systems | Cosign policy-controller (Phase 11/12 strict) — only signed images |
| A.8.20 | Networks security | Cilium NetworkPolicy + L7 SVID enforcement |
| A.8.21 | Security of network services | Service mesh mTLS (Phase 10) |
| A.8.22 | Segregation of networks | Cluster-per-env + namespace isolation + Cilium L3/L4 |
| A.8.23 | Web filtering | Egress proxy + DNS allowlist |
| A.8.24 | Use of cryptography | All in scope; algorithm whitelist documented `post-quantum-readiness.md` |
| A.8.25 | Secure development life cycle | TDD + acceptance docs + code review + ASVS L3 |
| A.8.26 | Application security requirements | OWASP ASVS L3 `asvs-l3-self-assessment.md` |
| A.8.27 | Secure system architecture and engineering principles | STRIDE threat model + clean architecture |
| A.8.28 | Secure coding | go-style-reviewer + skill `evgeniy` + skill `godzila` |
| A.8.29 | Security testing in development and acceptance | Integration tests + newman E2E + Phase 12 fuzz + chaos |
| A.8.30 | Outsourced development | Same coding standards for contractors |
| A.8.31 | Separation of development, test and production environments | k3d dev / staging cluster / prod cluster |
| A.8.32 | Change management | KAC YouTrack + branch protection + acceptance gates |
| A.8.33 | Test information | Synthetic test data only; PII anonymization |
| A.8.34 | Protection of information systems during audit testing | Pentest readiness env (`provision-pentester-env.sh`) |

## Audit timeline (typical)

1. **Month 1-2**: Gap assessment with consultant (optional but recommended).
2. **Month 2-3**: Remediation of gaps; documentation finalization.
3. **Month 3-6**: Implementation evidence accrual.
4. **Month 6-9**: Stage 1 audit (document review) + Stage 2 audit (operational evidence).
5. **Month 9-12**: Cert issuance.
6. **Annual**: Surveillance audit.
7. **Year 3**: Recertification (full audit).

## References

- ISO/IEC 27001:2022: https://www.iso.org/standard/27001
- ISO/IEC 27002:2022 (implementation guidance)
- ISO 27017 (cloud-services controls) — parallel adoption recommended
- ISO 27018 (PII protection in public-cloud) — for GDPR alignment
