# OpenID Foundation Self-Certification — Kachō Cloud

**Standard**: OpenID Foundation OIDC Self-Certification (Authorization Code Flow + Implicit removed)
**Component**: Hydra (OAuth2/OIDC issuer) + kacho-iam + Kratos (IdP)
**Date**: 2026-05-20
**Status**: READY (run `tests/conformance/oidc/run-oidc-conformance.sh` to generate evidence)
**Submission**: NOT YET (gated on GA-launch + bug-fix iteration)

## Scope

Kachō Cloud submits the following OIDC profiles for self-certification:
- **Authorization Code with PKCE** (FAPI 2.0 baseline)
- **Implicit Flow** — explicitly NOT submitted (deprecated, removed Phase 2)
- **Refresh Token Rotation** (single-use rotation with family-detection)
- **RP-Initiated Logout** (Phase 2)
- **Back-Channel Logout** (Phase 2)
- **DPoP** (RFC 9449, Phase 2)
- **mTLS Client Authentication** (Phase 10)

## Compliance Checklist

### Authentication Flows
- [x] Authorization Code with PKCE S256
- [x] PKCE plain method NOT supported (Hydra config `oauth2.pkce.enforced: true`)
- [x] Authorization Code without PKCE rejected for public clients
- [x] Implicit flow disabled (`oauth2.allowed_response_types` does not include `id_token` direct)
- [x] Hybrid flow disabled
- [x] Refresh token rotation enabled with reuse-detection
- [x] Token expiration: access 15min, id_token 15min, refresh 30d

### Token Format
- [x] JWT-encoded tokens (no opaque)
- [x] Algorithm: `ES256` default (whitelist: ES256, ES384, EdDSA, RS256, PS256)
- [x] `none` algorithm rejected
- [x] HS256/HS384 with shared secret rejected (asymmetric only)

### Claims
- [x] `iss` validates issuer URL exactly
- [x] `aud` validates client_id present
- [x] `iat`, `exp` standard
- [x] `auth_time` set
- [x] `nonce` echoed back if present in request
- [x] `acr` claim populated (`aal2` / `aal3`)
- [x] `amr` claim populated (`["pwd","mfa","hwk","fpt"]` per session)

### Endpoint Conformance
- [x] `/.well-known/openid-configuration` discovery
- [x] `/.well-known/jwks.json` exposes public keys
- [x] Authorization endpoint: `/oauth2/auth`
- [x] Token endpoint: `/oauth2/token`
- [x] Userinfo endpoint: `/userinfo`
- [x] Revocation endpoint: `/oauth2/revoke`
- [x] Introspection endpoint: `/oauth2/introspect` (mTLS-bound clients only)
- [x] End-session endpoint: `/oauth2/sessions/logout`

### Security
- [x] HTTPS enforced on all endpoints
- [x] TLS 1.3 only (TLS 1.2 with explicit cipher whitelist as fallback)
- [x] HSTS header on all endpoints (1y, includeSubDomains, preload)
- [x] Cookie attributes: Secure, HttpOnly, SameSite=Strict
- [x] CSRF protection via `state` parameter
- [x] `redirect_uri` exact match (no wildcard)
- [x] PKCE S256 mandatory for public clients
- [x] DPoP-bound access tokens (RFC 9449)
- [x] mTLS-bound access tokens (RFC 8705) for confidential clients
- [x] Client authentication: `private_key_jwt`, `tls_client_auth`, `client_secret_jwt`
- [x] `client_secret_basic` allowed but discouraged for confidential

### Privacy
- [x] Subject identifier type `pairwise` available (per-client subject)
- [x] No PII in JWT audience-readable claims unless requested

### CORS
- [x] CORS allow-list configured per-client `allowed_cors_origins`
- [x] Preflight OPTIONS handled

## Test execution

Run conformance suite locally or in CI:

```bash
# From kacho-deploy
./tests/conformance/oidc/run-oidc-conformance.sh \
    --domain="${KACHO_DOMAIN:-api.kacho.cloud}" \
    --client-id="${OIDC_TEST_CLIENT_ID}" \
    --client-secret="${OIDC_TEST_CLIENT_SECRET}" \
    --output-dir="./oidc-conformance-results"
```

The script wraps the OpenID Foundation conformance suite Docker image
(`openid/conformance-suite`) and runs the following profiles:
- `oidcc-basic`
- `oidcc-implicit` (must FAIL — implicit deprecated)
- `oidcc-hybrid` (must FAIL — hybrid disabled)
- `oidcc-rp-initiated-logout`
- `oidcc-back-channel-logout`
- `fapi2-baseline-ci-id1`
- `fapi2-message-signing-id1`

Output: JSON report consumed by `report_generator.py` → HTML report.

## Submission process

Once formal certification is desired (post-GA):

1. Register at https://openid.net/certification/
2. Pay submission fee (currently $750 OIDF members / $2000 non-members)
3. Upload conformance suite JSON report
4. Sign certification agreement
5. List in https://openid.net/certified-open-id-developer-tools/

## References

- OpenID Connect Core 1.0: https://openid.net/specs/openid-connect-core-1_0.html
- OpenID Conformance Suite: https://gitlab.com/openid/conformance-suite
- OpenID Certification: https://openid.net/certification/
- FAPI 2.0 Baseline: https://openid.bitbucket.io/fapi/fapi-2_0-baseline.html
- RFC 9449 (DPoP)
- RFC 8705 (Mutual-TLS Client Authentication)
