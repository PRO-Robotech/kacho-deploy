# Post-Quantum Readiness and Crypto Agility — Kachō Cloud

**Date**: 2026-05-20
**Status**: PLAN DOCUMENTED; ACTIVATION GATED on ecosystem support
**Related**: ASVS L3 V6.5.1, V6.5.2, V6.5.3

## Scope

This document defines how Kachō Cloud transitions to post-quantum cryptography (PQC) once browsers, OS libraries, and HSMs support standardized PQ algorithms (NIST PQC Round 4 finalists: ML-KEM, ML-DSA, SLH-DSA).

## Crypto agility (V6.5.2)

Kachō was designed for crypto-agility from day one: algorithm choices are runtime-configurable, not compile-time.

### Algorithm parameters — runtime-config

| Component | Configuration knob | Default | Override path |
|-----------|---------------------|---------|---------------|
| Hydra JWT signing | `system.token.signing_alg` | `ES256` | values.prod.yaml `hydra.config.system.token.signing_alg` |
| Hydra JWT signing keys (per-tenant) | JWKS rotation worker generates fresh `kid` with configured alg | `ES256` | env var `HYDRA_JWT_SIGNING_ALG` |
| Kratos WebAuthn COSE algs | `webauthn.config.algorithms[]` | `[-7, -8, -257]` (ES256, EdDSA, RS256) | values.prod.yaml `kratos.config.selfservice.methods.webauthn.config.algorithms` |
| TLS ingress cipher suites | nginx `ssl_ciphers` | `TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:...` | values.prod.yaml `ingress.tls.cipherSuites` |
| TLS server protocol | nginx `ssl_protocols` | `TLSv1.3` | values.prod.yaml `ingress.tls.minProtocol` |
| Postgres TDE algorithm | LUKS `--cipher` | `aes-xts-plain64` | Terraform `kacho_postgres_pv_cipher` |
| SAML signature alg | Jackson `xml_signature_algorithm` | `rsa-sha256` | values.prod.yaml `kacho-iam.saml.signature_alg` |
| HSM key gen alg (JWKS) | PKCS#11 `CKM_ECDSA_KEY_PAIR_GEN` with `secp256r1` | `ES256` | env var `HSM_JWKS_KEY_ALG` |
| Audit log Merkle hash | `sha256` (NIST FIPS 180-4) | `sha256` | env var `KACHO_AUDIT_MERKLE_HASH` |
| Argon2id parameters | Kratos `argon2id` config | `m=64MiB, t=3, p=4` | values.prod.yaml `kratos.config.identity.default_password_hashing.argon2id` |

### Test: algorithm swap is one-config-change

The "one-config-change" property is verified by integration test `tests/conformance/crypto-agility/`:

1. Deploy fresh stack with `signing_alg=ES256`.
2. Run authentication flow; verify JWT header `alg=ES256`.
3. `helm upgrade --set hydra.config.system.token.signing_alg=PS512`.
4. Trigger JWKS rotation; wait 60s.
5. Re-authenticate; verify JWT header `alg=PS512`.
6. Verify old tokens still valid (verifier reads `kid` and resolves to correct alg).
7. After max(access_token_TTL + grace=15min), retire old key from JWKS.

---

## Post-quantum (PQ) transition plan

### Current state (2026-Q2)

- TLS 1.3 with X25519 / secp256r1 ECDH.
- JWT signing with ES256 (P-256 ECDSA) / RS256 / EdDSA (Ed25519).
- WebAuthn with P-256 ECDSA (FIDO Alliance default).
- All algorithms classical-only.

### Hybrid TLS (planned, Phase 13+)

When browsers ship NIST PQC support (Chrome `X25519Kyber768Draft00` already in experiment; Firefox + Safari pending):

1. **Hybrid key exchange in TLS 1.3**:
   - Cloudflare Edge + Envoy ingress: `X25519MLKEM768` (NIST FIPS 203 ML-KEM).
   - Both classical (X25519) and PQ (ML-KEM) used; either being broken does not compromise the session.
   - Cipher list update in Envoy:
     ```yaml
     common_tls_context:
       tls_params:
         tls_minimum_protocol_version: TLSv1_3
         cipher_suites: [...]  # AES-256-GCM with X25519+ML-KEM-768 KEM
     ```

2. **Hybrid signing for JWT** (post-NIST FIPS 204 / ML-DSA):
   - Hydra `signing_alg=ML-DSA-65` once go-jose supports it.
   - Hybrid mode: JWT has both `alg=ES256` (current) and `alg2=ML-DSA-65` signatures (composite).
   - Phase out classical after PQ ecosystem maturity (~2028-2030).

3. **WebAuthn PQ authenticators**:
   - FIDO Alliance roadmap: 2027+ for PQ-capable hardware keys.
   - Kratos COSE algorithm list expanded once authenticators ship.
   - Kachō pre-emptive: `kratos.config.selfservice.methods.webauthn.config.algorithms = [-7, -8, -257, -50, -51]` (last two reserved for ML-DSA-44/65).

### HSM PQ support

- Current HSMs (AWS CloudHSM v2, YubiHSM 2) — no PQ yet.
- Awaiting FIPS 140-3 PQ-certified modules (expected 2027).
- Migration plan: dual-issuance from old + new HSM during transition.

### Risk-driven prioritization

| Asset | Cryptographic protection | PQ-priority | Reason |
|-------|--------------------------|-------------|--------|
| Long-lived JWT (refresh) | RS256 / ES256 | HIGH | Harvest-now-decrypt-later threat |
| Audit-log signing | RS256 | HIGH | 365-day retention; PQ-readable in future |
| TLS session | X25519 | MEDIUM | Ephemeral; only session compromise |
| Database TDE | AES-256 | LOW | Symmetric — quantum-Grover-resistant (effectively 128-bit) |
| Argon2id password hashes | symmetric | LOW | Symmetric |

## Activation gates

Activation of post-quantum mode is gated on **all** of:

1. NIST FIPS 203/204/205 standards published (achieved 2024-08).
2. Major HSM vendors offer FIPS 140-3 PQ-certified modules (target: 2027).
3. ≥80% of Kachō user-base on browsers supporting hybrid TLS (track via Cloudflare Edge analytics).
4. Go ecosystem supports ML-DSA in `go-jose` / `crypto/ml-dsa` (track upstream issues).
5. WebAuthn L3+ spec includes PQ algorithms in COSE registry.

Approval: Kachō Security Team + CTO + external pentest review.

## References

- NIST PQC Project: https://csrc.nist.gov/projects/post-quantum-cryptography
- FIPS 203 (ML-KEM): https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.203.pdf
- FIPS 204 (ML-DSA): https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf
- Cloudflare PQ Day: https://blog.cloudflare.com/pq-2024/
- Chrome `X25519Kyber768Draft00`: https://blog.chromium.org/2023/08/protecting-chrome-traffic-with-hybrid.html
- ASVS L3 V6.5.1–V6.5.3 evidence
