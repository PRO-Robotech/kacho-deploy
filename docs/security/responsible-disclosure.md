# Responsible Disclosure Policy — Kachō Cloud

**Effective**: 2026-05-20
**Version**: 1.0
**Public URL**: https://kacho.cloud/security/disclosure (when published)

## We welcome security research

Kachō Cloud is committed to working with security researchers to verify and address potential vulnerabilities in our platform. We appreciate your help in keeping our users safe and providing a safe-harbor framework for good-faith research.

## In scope

The following Kachō Cloud production properties are in scope:

- `https://api.{{ domain }}` — Public API (api-gateway)
- `https://app.{{ domain }}` — UI / BFF
- `https://hydra.{{ domain }}` — OAuth2 / OIDC issuer
- `https://kratos.{{ domain }}` — IdP self-service flows
- `https://kacho.cloud` — Marketing website
- Public-facing kacho-* gRPC services
- Mobile SDKs (when published)
- All assets served from `*.kacho.cloud` (configurable domain)

## Out of scope (please report to upstream)

- **Kratos** (IdP) — report to https://github.com/ory/kratos/issues
- **Hydra** (OIDC issuer) — report to https://github.com/ory/hydra/issues
- **OpenFGA** — report to https://github.com/openfga/openfga/issues
- **Cilium** — report to https://github.com/cilium/cilium/issues
- **SPIRE** — report to https://github.com/spiffe/spire/issues
- **Postgres / Kafka / ClickHouse** — report to upstream
- 3rd-party service providers (Cloudflare, AWS, GCP) — report to them

## How to report

Send detailed report to: **security@kacho.cloud**

PGP-encrypted preferred: see https://kacho.cloud/.well-known/pgp-key.txt

Please include:
1. Title (short summary of vulnerability)
2. CVSS 3.1 vector + score (your estimate)
3. Affected component / endpoint / version
4. Step-by-step reproduction (text or video)
5. Proof-of-concept (do NOT include any actual exploited data)
6. Impact assessment
7. Suggested remediation (if any)
8. Your name / handle for acknowledgment (or "anonymous")

We will acknowledge receipt within **24 hours** (business days; weekends up to 72 hours).

## Severity & SLA

| Severity | CVSS | Response Time | Fix SLA | Reward (USD) |
|----------|------|---------------|---------|--------------|
| Critical | 9.0-10.0 | 4h business hours | 24h | $5,000 - $50,000 |
| High | 7.0-8.9 | 24h | 7d | $1,500 - $10,000 |
| Medium | 4.0-6.9 | 3 business days | 30d | $250 - $2,000 |
| Low | 0.1-3.9 | 7 business days | 90d | $50 - $500 |
| Informational | N/A | 14 business days | best-effort | Acknowledgment |

Final severity classification is determined by Kachō Cloud security team.

## Safe harbor

Provided you comply with this policy, Kachō Cloud will:

- NOT take legal action against you under the Computer Fraud and Abuse Act (CFAA) or applicable laws of your jurisdiction.
- NOT report you to law enforcement.
- Make reasonable efforts to publicly credit you (with your consent).

In exchange, you must:

- Limit testing to **only those systems in scope**.
- Avoid privacy violations, degradation of service, destruction of data, and disruption of production.
- **Do NOT exploit a vulnerability beyond what is necessary** to confirm its existence.
- **Do NOT exfiltrate data** that does not belong to you. If a vulnerability allows access to data, please:
  - Document only what is necessary to prove existence (e.g., user count, schema, a single test-account record).
  - Stop testing further.
  - Notify Kachō security team immediately.
- **Do NOT engage in social engineering** of Kachō employees / customers / vendors.
- **Do NOT use automated scanners** in a way that disrupts service (no high-rate DoS-style fuzzing).
- Provide Kachō reasonable time to respond before public disclosure (recommended: 90 days, negotiable).

## Public disclosure

After fix is deployed:
- We will work with you on a public disclosure timeline.
- Default: 90 days from initial report (negotiable based on severity).
- A CVE is requested for High / Critical issues.
- Researchers are publicly acknowledged on https://kacho.cloud/security/acknowledgments (with consent).

## Out of scope (general categories of "vulnerability" we don't accept)

- Missing security headers without demonstrable exploitation
- Auto-fillable form fields
- Self-XSS without victim interaction
- TLS configuration "weaknesses" already mitigated (e.g., TLS 1.2 still supported with strong ciphers — acceptable)
- Clickjacking on pages with no sensitive actions
- Open redirect requiring user interaction without security impact
- Brute-force / rate-limit / account enumeration without specific impact
- "Best practices" suggestions without concrete vulnerability
- Lack of HSTS preload submission
- DDoS attacks (please use Cloudflare's responsible reporting channel)
- Findings from automated scanners without manual validation
- Issues already known internally (we publish acknowledged researchers on the page above; check before reporting)

## Hall of Fame

Researchers who have responsibly disclosed vulnerabilities to Kachō Cloud are listed at https://kacho.cloud/security/acknowledgments (with consent).

## Bug Bounty Program

Once we engage with HackerOne (User-action prerequisite, see `bug-bounty-program.md`), this policy will be supplemented by detailed bounty terms hosted on HackerOne. Until then, rewards may be ad-hoc (cash, swag, acknowledgment).

## Contact

- **Email**: security@kacho.cloud
- **PGP**: https://kacho.cloud/.well-known/pgp-key.txt
- **GitHub Security Advisories**: per-repo at https://github.com/PRO-Robotech/kacho-*/security/advisories

Thank you for helping keep Kachō Cloud safe!
