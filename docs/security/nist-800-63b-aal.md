# NIST SP 800-63B — AAL Implementation in Kachō Cloud

**Standard**: NIST Special Publication 800-63B (Digital Identity Guidelines — Authentication and Lifecycle Management)
**Date**: 2026-05-20
**Status**: SELF-ASSESS PASS

## Overview

NIST 800-63B defines three Authenticator Assurance Levels (AAL1/2/3). Kachō Cloud implements AAL2 (default for user actions) and AAL3 (admin / high-risk operations).

| Level | Description | Kachō Implementation |
|-------|-------------|----------------------|
| AAL1 | Single-factor | Not used (rejected during E2 design) |
| **AAL2** | Multi-factor cryptographic device or SF + memorized secret | **Passkey** (single-factor cryptographic device with user-verification) |
| **AAL3** | Multi-factor hardware cryptographic device | **Passkey + TOTP** OR **Passkey-PIV (FIDO2 L2)** |

## AAL2 — default user authentication

### Authenticator type
- **WebAuthn Passkey** (FIDO2 credential type `public-key`).
- Discoverable credentials (`residentKey: required`).
- User Verification REQUIRED (`userVerification: required`).
- Attestation type `direct` for production (passes FIDO MDS3 validation).

### Verifier requirements
- Origin binding: WebAuthn `rpId` = `{{ .Values.kacho.domain }}` (configurable).
- Challenge: 32-byte random from CSPRNG, single-use, 5min TTL.
- Counter monotonicity: verified server-side; rejection if regression detected (cloned authenticator detection).
- COSE algorithm whitelist: `ES256`, `ES384`, `EdDSA`, `RS256` (Kratos config `kratos.session.webauthn.config.algorithms`).

### Session
- Idle timeout: 15min (sliding).
- Absolute lifetime: 12 hours.
- Reauthentication: required for sensitive changes (ACR step-up to `aal3`).

### Replay-resistance
- WebAuthn `signCount` monotonic check.
- DPoP-bound JWT `cnf:jkt` claim ties access-token to user-private-key.
- DPoP-replay LRU cache (jti, 120s TTL, 100k size).

### Implementation evidence
- Kratos config: `helm/umbrella/charts/kratos/values.yaml § webauthn`
- DPoP fuzz target: `kacho-iam/internal/apps/kacho/api/authn/dpop/fuzz_dpop_parser_test.go`
- Audit logging: every authentication event → Kafka audit-topic with method=webauthn

---

## AAL3 — admin / high-risk

### Trigger conditions
ACR step-up to `aal3` is required for:
- Break-glass operations (Phase 7).
- Identity provider config changes (kacho-iam admin RPCs).
- Resource deletion / cross-tenant moves.
- Audit pipeline configuration changes.
- HSM key rotation operations.

### Authenticator combination

Option A: **Passkey (FIDO2 L2) + TOTP**
- Passkey provides "something you have" + "something you are" (biometric UV).
- TOTP provides additional "something you know" (memorized secret, 30s window).

Option B: **Single-device AAL3-class authenticator**
- FIDO2 hardware key with PIV (e.g., YubiKey 5 Series with FIPS-validated firmware).
- AAGUID validated against FIDO MDS3 metadata; metadata-statement attribute `aaguid_certifications` must contain `FIDO_L2_or_higher`.

### Verifier requirements (in addition to AAL2)
- ACR claim `aaguid_certified_l2: true` in JWT (set by api-gateway after MDS lookup).
- TOTP secret length ≥ 128 bits (HMAC-SHA256, RFC 6238).
- Reauthentication interval: 12 hours (matches absolute session lifetime).

### Step-up flow
1. User initiates sensitive action.
2. api-gateway middleware checks `acr` claim in JWT.
3. If `acr < aal3`: redirect to Kratos `step_up` flow with `aal=aal3` query param.
4. Kratos challenges with WebAuthn UV + TOTP.
5. Upon success, Hydra issues fresh JWT with `acr=aal3`, `auth_time=<now>`.
6. Original action replayed with new JWT.

### Implementation evidence
- ACR enforcement: `kacho-api-gateway/internal/middleware/acr.go` (Phase 4)
- Step-up flow: Kratos `selfservice.flows.login.after.password.hooks` mapping
- TOTP storage: `kratos.credentials.config` (Argon2id-encrypted at rest)

---

## Session management (NIST 800-63B §7)

| Requirement | Kachō Implementation |
|-------------|----------------------|
| Session secret unguessable | Hydra issues 256-bit random kid + signed JWT |
| Session binding to subject | DPoP `cnf:jkt` binds to user-private-key |
| Reauthentication enforced | ACR step-up + max-age check |
| Session termination on logout | Kratos selfservice logout + back-channel logout to RP via Hydra |
| Session inactivity timeout | 15min idle sliding |
| Session absolute timeout | 12h regardless of activity |
| Session cookie attributes | `Secure; HttpOnly; SameSite=Strict; __Host-` prefix |
| Cross-site request forgery | DPoP origin-binding + same-site cookies |

---

## Compromised credential mitigations

| Scenario | Detection | Response |
|----------|-----------|----------|
| Phished password (legacy auth) | Kratos `pwned_passwords` check | Forced password change + breach notification |
| Authenticator counter regression | WebAuthn signCount tracking | Audit alert + force re-registration |
| Token theft (replay) | DPoP jti cache + iat freshness | Reject + audit alert |
| Refresh-token reuse | Hydra family-tracking | Revoke entire token family + force login |
| Session hijack | Source-IP / geographic anomaly | Step-up to AAL3 + alert via CAEP |

---

## Identity proofing reference (IAL — out of scope this doc)

NIST 800-63A defines IAL (Identity Assurance Levels). Kachō currently operates at IAL1 (self-asserted identity for end users). Higher IAL (IAL2 with KYC, IAL3 with in-person proofing) is **deferred** — applicable when financial / regulated workloads ship.

---

## References

- NIST SP 800-63B (rev 3): https://pages.nist.gov/800-63-3/sp800-63b.html
- FIDO MDS3 metadata: https://fidoalliance.org/metadata/
- WebAuthn L3 spec: https://www.w3.org/TR/webauthn-3/
- RFC 9449 (DPoP)
- Kachō ASVS L3 V2.7.6 evidence (FIDO MDS validation): `asvs-l3-self-assessment.md`
