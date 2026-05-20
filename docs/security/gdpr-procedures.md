# GDPR Procedures — Kachō Cloud

**Regulation**: General Data Protection Regulation (EU 2016/679)
**Date**: 2026-05-20
**Status**: PROCEDURES DOCUMENTED + IMPLEMENTED + DRILLED
**DPO**: dpo@kacho.cloud (when role designated; until then security@kacho.cloud)

## Scope

Kachō Cloud processes the following categories of personal data:
- **Identifiers**: email, username, user_id, external_id (OIDC sub)
- **Authentication**: WebAuthn credentials (public keys + counter), TOTP secrets, password hashes (Argon2id)
- **Profile**: display name, locale, timezone (optional)
- **Activity**: login timestamps, IP addresses, user-agents, session metadata
- **Authorization**: roles, groups, access bindings
- **Audit**: all administrative actions

Kachō Cloud does NOT process:
- Special category data (health, biometric for identification, sex life, racial/ethnic, political, religious)
- Children's data (we have a 16+ age policy)
- Real-name verification documents
- Payment card data (PCI scope handled by Stripe externally)

## Article 17 — Right to Erasure ("Right to be Forgotten")

### Implementation (Phase 7)
1. User initiates erasure request via UI: `app.<domain> > Account > Delete my account`.
2. Selfservice flow:
   - Confirm intent (re-authentication with WebAuthn).
   - Show what will be deleted + what will be retained (and why — audit log w/ legal basis).
   - 30-day grace period (allow undo).
3. After 30 days (cron `gdpr-erasure-worker`):
   - Delete `kacho_iam.users` row.
   - Cascade to `accounts.owner_user_id IS NULL` (or transfer ownership pending).
   - Delete `service_accounts.created_by_user_id` (set to null/system).
   - Delete `kratos.identities` row.
   - Delete `openfga` tuples involving user.
   - Mark `audit-log` entries with `pii_redacted=true` (keep audit retention; redact subject_email to `<redacted>`).
   - Trigger `caep-subscriber` SET event to downstream RP for federated logout.
4. Verify erasure (worker post-action) — query each affected table for residual references.
5. Email confirmation to user (or to alternate email if account purged).

### Audit log retention exception
- Audit-log entries are RETAINED for the legal-basis period (regulated workloads: 7y; standard: 1y).
- Subject identifiers ARE redacted to pseudonymized hash; activity event remains.
- This is permitted under GDPR Article 17(3)(e) (defence of legal claims).

### SLA
- Acknowledgment: 72 hours
- Completion: 30 days (Article 12(3))

### Files
- Worker: `kacho-iam/internal/apps/kacho/api/admin/gdpr_erasure_worker.go`
- Verification: `kacho-iam/internal/apps/kacho/api/admin/gdpr_verification_worker.go`
- UI flow: `kacho-ui/src/pages/account/Delete.tsx`

## Article 15 — Right of Access (Data Portability)

### Implementation
1. User initiates via UI: `app.<domain> > Account > Export my data`.
2. Asynchronous worker:
   - Queries all tables referencing user_id (across kacho_iam + kacho_vpc + kacho_compute + audit).
   - Bundles into JSON + CSV.
   - Encrypts with user-provided WebAuthn-derived key (so admins cannot read).
   - Uploads to S3 with signed URL (1h TTL).
3. Notification to user via email.

### SLA
- Acknowledgment: 72 hours
- Completion: 30 days (Article 12(3))

### Files
- Worker: `kacho-iam/internal/apps/kacho/api/admin/gdpr_export_worker.go`

## Article 18 — Right to Restriction

### Implementation
- User flags account as "restricted" via UI.
- All Kachō Cloud servers refuse mutations on user's records.
- Data preserved but no further processing.
- Authorization Check returns "PermissionDenied" with custom message.

## Article 32 — Security of Processing

Required:
- (a) Pseudonymization and encryption → AES-XTS-256 Postgres TDE + Argon2id passwords + HSM-protected JWKS
- (b) Confidentiality, integrity, availability, resilience → TLS 1.3 + mTLS SPIRE + multi-region active-active + Litmus chaos drills
- (c) Restore availability and access → Postgres WAL-G backup + 1h RPO + DR drills
- (d) Process for regularly testing → ASVS L3 self-assess + external pentest + chaos game-days

All four are addressed (see `asvs-l3-self-assessment.md`).

## Article 33 — Breach Notification

### Detection
- Multi-source alerts:
  - Audit pipeline anomaly detection (Phase 9)
  - SIEM via Kafka Connect (Phase 9)
  - Cloud-provider security advisories (AWS GuardDuty, GCP SCC)
  - AlertManager → PagerDuty
- 24/7 on-call rotation

### Notification SLA
- **To Supervisory Authority** (data protection authority): 72 hours from awareness (Article 33(1))
- **To Affected Data Subjects** (if high risk): "without undue delay" (Article 34); Kachō aims for 7 days

### Notification process
1. **Detection** — incident alert fires.
2. **Triage** — on-call assesses severity within 1h.
3. **Containment** — isolate affected systems.
4. **Investigation** — forensics on audit-pipeline (Kafka + Merkle hash chain enables tamper-proof timeline).
5. **DPO notification** — security team informs DPO within 6h.
6. **Authority notification** — DPO files to authority within 72h.
7. **User notification** — email + in-app banner if high-risk (>1000 users affected OR sensitive data category).
8. **Public disclosure** — coordinated with PR + legal; typically 7-14 days post-fix.
9. **Post-mortem** — internal review + KAC ticket + acceptance criteria for prevention.

### Files
- Runbook: `docs/runbooks/security-incident-response.md`
- Communication templates: `docs/templates/breach-notification-*.md`

## Article 24/25 — Privacy by Design / Privacy by Default

### Privacy by Default
- New user accounts: minimum data collection (email + display name only)
- New resources: private by default (`access_level=private`); requires explicit share
- Cookies: no tracking cookies; functional-only (session + CSRF)
- Telemetry: anonymized; per-user opt-out via UI

### Privacy by Design (Article 25)
- Per-service DB (запрет #8) limits blast radius
- Tenant interceptor enforces tenant-scope on every query
- OpenFGA Check enforces fine-grained access control
- Audit pipeline records all access (accountability)
- HSM-protected signing keys (defense in depth)

## Article 30 — Records of Processing Activities (RoPA)

Maintained at `docs/legal/ropa.md` (not committed to public repo). Contains:
- Each processing activity
- Purpose
- Categories of data
- Recipients
- Cross-border transfers
- Retention periods
- Security measures

## Data Processing Agreement (DPA)

Standard DPA template at `docs/legal/dpa-template.md`. Customers can sign as part of onboarding (post-GA).

## Cross-border Transfers (Article 44–49)

- Default: EU customer data stays in EU regions (multi-region failover within EU when possible)
- Transfers to US: Standard Contractual Clauses (SCC) per 2021/914 (where applicable)
- No transfers to countries without Adequacy Decision unless SCC + Transfer Impact Assessment (TIA) on file

## Drill (Article 32(d))

Quarterly drill:
- Tabletop exercise — simulate breach scenario
- Verify detection → containment → notification → recovery within SLA
- Update runbook based on lessons

Reference Phase 12 Litmus chaos `caep-subscriber-down` + audit-pipeline experiments verify breach-detection paths.

## References

- GDPR full text: https://gdpr-info.eu/
- ICO breach notification guide (UK ICO): https://ico.org.uk/for-organisations/guide-to-data-protection/guide-to-the-general-data-protection-regulation-gdpr/personal-data-breaches/
- EDPB Guidelines on Breach Notification (01/2021): https://edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-012021-examples-regarding-personal-data-breach_en
- NIST 800-66 (HIPAA framework — parallel-applicable concepts): https://csrc.nist.gov/pubs/sp/800/66/r2/final
