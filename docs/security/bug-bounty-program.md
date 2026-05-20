# Bug Bounty Program — Kachō Cloud

**Status**: PREP DONE; HackerOne engagement is a **User-action**
**Date**: 2026-05-20

> Operating a bug bounty program requires:
>   - Legal agreement with bounty platform (HackerOne primary, Bugcrowd as fallback)
>   - Budget allocation for rewards ($50k–$250k annual reserve recommended)
>   - Triage capacity (typically 1 FTE security engineer + on-call rotation)
>   - Internal escalation paths
>   - Public disclosure policy (done — see `responsible-disclosure.md`)
>
> This document outlines the preparation work done in Phase 12 and the
> remaining User-actions to launch.

## Platform selection — DECISION

**Primary**: HackerOne (https://hackerone.com)
- Industry-leading triage quality
- Strong researcher base (~600k registered)
- Integration with Slack / JIRA / GitHub
- Triage-as-a-service available (~$20k/month) for early stage

**Fallback**: Bugcrowd (https://bugcrowd.com)
- Used if HackerOne quoting becomes uncompetitive
- Comparable researcher base

**Out**: Synack — invite-only researcher pool not aligned with our open culture.

## Scope (initial)

In-scope assets (matches `responsible-disclosure.md`):
- Production API endpoints (`api.{{ domain }}`, `app.{{ domain }}`, `hydra.{{ domain }}`, `kratos.{{ domain }}`)
- Marketing website (`kacho.cloud`)
- Mobile SDKs (when published)
- iOS / Android apps (when published)

Out-of-scope:
- Upstream OSS (Kratos, Hydra, OpenFGA, Cilium, SPIRE) — researchers should report there
- 3rd-party services (Cloudflare, AWS, GCP)
- DDoS attacks
- Social engineering of employees

## Reward tiers

(See `responsible-disclosure.md` for full table; HackerOne config mirrors.)

- **Critical (9.0-10.0)**: $5,000 - $50,000
- **High (7.0-8.9)**: $1,500 - $10,000
- **Medium (4.0-6.9)**: $250 - $2,000
- **Low (0.1-3.9)**: $50 - $500
- **Informational**: Acknowledgment only

Bonuses (above base reward):
- Critical chain (>1 vuln in same report): +25%
- Excellent report quality (clear repro + impact + remediation): +25%
- First report of issue class (e.g., first IDOR found): +25%

## Triage process

```
Submission → HackerOne Triage (1st pass) →
  Kachō Security Team (CVSS confirm, severity, KAC ticket creation) →
  Engineering (fix branch, PR) → Verification → Reward payment + Public disclosure
```

SLA per `responsible-disclosure.md` table.

## Onboarding checklist (User-action)

- [ ] **Legal**: counsel review of HackerOne master service agreement + safe-harbor terms
- [ ] **Finance**: budget allocation for first year ($150k-$250k recommended)
- [ ] **Operations**: Slack #bug-bounty-triage channel + PagerDuty rotation
- [ ] **Engineering**: GitHub Security Advisories enabled on each `kacho-*` repo
- [ ] **HackerOne contract signed** + Kachō account setup
- [ ] **Triage agreement** — internal SLA for triage response (24h business)
- [ ] **Reward fulfillment** — Wise / wire / ACH payment integration
- [ ] **Researcher landing page** — UI at https://kacho.cloud/security/bounty
- [ ] **Public launch announcement** — blog post + Twitter / LinkedIn
- [ ] **Initial scope** validated by HackerOne triage team
- [ ] **Hall of Fame page** at https://kacho.cloud/security/acknowledgments

## Pre-launch private VDP phase (recommended, 3 months)

Before public bug bounty launch, run a private Vulnerability Disclosure Program:
- Invite 20-40 trusted researchers
- No financial rewards (acknowledgment + swag)
- Validates scope, triage SLA, fix-deployment flow
- Catches "easy" vulnerabilities before public launch
- Builds reputation with researcher community

## Public launch criteria

Do not announce public bug bounty until:
- [ ] All 14 acceptance docs APPROVED (KAC-127 acceptance gate)
- [ ] OWASP ASVS L3 self-assessment PASS (`asvs-l3-self-assessment.md`)
- [ ] Annual pentest from Phase 12 completed + High/Critical fixes deployed
- [ ] Private VDP phase complete (3+ months)
- [ ] At least 1 successful Litmus chaos game-day (Phase 12)
- [ ] Triage SLA proven in private VDP phase
- [ ] Public roadmap stable (no major API changes in next 90 days)

## Annual review

Each year:
- Total submissions / valid / dupes
- Average CVSS distribution
- Average response time
- Average fix time
- Total reward payout
- Researcher retention
- Scope-adjustments for next year

## References

- HackerOne: https://www.hackerone.com/
- Bugcrowd: https://www.bugcrowd.com/
- Disclose.io safe-harbor templates: https://disclose.io/
- HackerOne Pentaceratops report (example program): https://hackerone.com/grammarly
