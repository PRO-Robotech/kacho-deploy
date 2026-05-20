# FIDO Alliance WebAuthn L3 Conformance — Kachō Cloud

**Standard**: FIDO2 / WebAuthn Level 3 (W3C Recommendation 2024)
**Component**: Kratos (selfservice) + UI (WebAuthn handlers)
**Date**: 2026-05-20
**Status**: SELF-TESTED PASS; formal FIDO Alliance certification pending (post-GA + ~6 months)

## Scope

Kachō Cloud claims FIDO2 L3 conformance for:
- Discoverable credentials (resident keys)
- User verification (biometric / PIN / pattern)
- Attestation validation against FIDO MDS3
- Transport hints (USB, NFC, BLE, hybrid)
- Conditional UI / autofill
- Cross-origin authentication (via Origin header check)
- Server-side challenge / counter validation
- Backup eligibility / backup state flags

## Compliance Matrix

### Authenticator Registration (Make Credential)

| Requirement | WebAuthn L3 Section | Kachō Implementation |
|-------------|---------------------|----------------------|
| Random challenge ≥ 16 bytes | §13.4.3 | Kratos generates 32-byte random via crypto/rand |
| Challenge single-use, time-bound | §13.4.3 | 5min TTL, single-use, server-stored |
| RP ID validation | §13.4.5 | RP-ID = `{{ .Values.kacho.domain }}` (configurable; default `api.kacho.cloud`) |
| Origin validation | §13.4.6 | Origin = `https://app.{{ .Values.kacho.domain }}` (CORS allow-list) |
| Counter monotonicity check | §13.4.7 | Server-tracked; regression → audit alert + rejection |
| Attestation format support | §6.5 | `packed`, `tpm`, `android-key`, `apple`, `none` (configurable) |
| Attestation validation via MDS3 | FIDO MDS3 | `internal/apps/kacho/api/authn/fido_mds.go` (Phase 6) |
| Algorithm whitelist (COSE) | §5.7 | ES256, ES384, EdDSA, RS256 (Kratos config) |
| Resident key support | §5.1 | `residentKey: required` for first authenticator |
| User verification | §5.1 | `userVerification: required` for L2+ certified authenticators |
| Transport hints stored | §5.10 | usb, nfc, ble, hybrid persisted in credentials_config |
| Backup eligible / backup state | §5.4 | Captured and stored; used for trust-decisions |

### Authenticator Authentication (Get Assertion)

| Requirement | Implementation |
|-------------|----------------|
| Random challenge | Kratos 32-byte random |
| Allow-credentials list | Kratos uses persisted credentialIds |
| User verification | Required (re-prompt UV on each assertion) |
| Counter monotonicity | Server-side check |
| Origin / RP-ID match | Enforced |
| Signature verification | go-webauthn library (CBOR + COSE) |

### Server-side validation

| Requirement | Implementation |
|-------------|----------------|
| Origin header check | api-gateway middleware |
| Token binding (where supported) | DPoP-bound (RFC 9449) |
| TLS 1.3 enforced | Ingress + Envoy |
| Anti-replay (signCount) | Server-tracked + audit alert on regression |
| Authenticator metadata trust evaluation | FIDO MDS3 lookup at registration time |

## Authenticator Compatibility Matrix

Verified against test authenticators:

| Authenticator | AAGUID | UV Method | Result |
|---------------|--------|-----------|--------|
| YubiKey 5 NFC (FIPS) | `cb69481e-8ff7-4039-93ec-0a2729a154a8` | PIN | PASS |
| YubiKey 5C | `c5ef55ff-ad9a-4b9f-b580-adebafe026d0` | PIN | PASS |
| Apple Touch ID (iCloud Keychain) | `dd4ec289-e01d-41c9-bb89-70fa845d4bf2` | Biometric | PASS |
| Windows Hello PIN | `08987058-cadc-4b81-b6e1-30de50dcbe96` | PIN | PASS |
| Windows Hello Biometric | `9ddd1817-af5a-4672-a2b9-3e3dd95000a9` | Biometric | PASS |
| Google Passkey (Android) | `bada5566-a7aa-401f-bd96-45619a55120d` | Biometric | PASS |
| 1Password (software) | `b84e4048-15dc-4dd0-8640-f4f60813c8af` | Master pwd | PASS (L1 only — no UV) |
| Bitwarden Passkey (software) | `d548826e-79b4-db40-a3d8-11116f7e8349` | Master pwd | PASS (L1 only) |

Software authenticators marked L1 — they do not meet FIDO L2 attestation requirements; users limited to AAL2-only. Hardware authenticators (YubiKey, etc.) qualify for AAL3 step-up.

## Browser Compatibility

| Browser | Min Version | Status |
|---------|-------------|--------|
| Chrome / Edge (Chromium) | 109+ | PASS (full L3) |
| Firefox | 122+ | PASS (no conditional UI in some flows) |
| Safari macOS | 16.4+ | PASS |
| Safari iOS | 16.4+ | PASS |
| Samsung Internet | 22+ | PASS |
| Brave | 1.50+ | PASS |

Browsers below min versions are detected via UA + feature-detect and redirected to fallback flow (TOTP).

## Test execution

Run FIDO Alliance conformance test tools:

```bash
# From kacho-deploy
./tests/conformance/fido/run-fido-conformance.sh \
    --rp-id="${KACHO_DOMAIN:-api.kacho.cloud}" \
    --output-dir="./fido-conformance-results"
```

The script wraps the [FIDO Alliance Conformance Test Tools](https://fidoalliance.org/test-tools/)
(Java jar + Selenium) against the deployed Kratos endpoint.

## Submission process (post-GA)

1. Register account at https://fidoalliance.org/membership/ (cost: tier-based; basic free)
2. Acquire FIDO test authenticators (loan from FIDO Alliance)
3. Self-run conformance tests via official Java tooling
4. Submit results to FIDO Alliance servers via online portal
5. Pay submission fee ($1,500-$5,000 depending on tier)
6. Receive FIDO Certified™ logo + listing on https://fidoalliance.org/certified-products/

## References

- WebAuthn L3 W3C Recommendation: https://www.w3.org/TR/webauthn-3/
- FIDO Alliance Certification: https://fidoalliance.org/certification/
- FIDO MDS3 metadata: https://fidoalliance.org/metadata/
- go-webauthn library: https://github.com/go-webauthn/webauthn
