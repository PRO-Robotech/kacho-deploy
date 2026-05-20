# Kachō Cloud — STRIDE Threat Model

**Methodology**: STRIDE per component
**Date**: 2026-05-20
**Scope**: kacho-iam, kacho-api-gateway, kacho-vpc, kacho-compute, Kratos, Hydra, OpenFGA, Kafka, ClickHouse, HSM, SPIRE
**Standard alignment**: ASVS L3 V1.1.1, V1.1.4

## Trust boundaries

```
Internet
   │  TLS 1.3
   ▼
Cloudflare WAF + DDoS
   │  mTLS
   ▼
Ingress (Envoy) ─── api-gateway ─── Cilium-mesh ─── { kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer }
                                                      │       │              │              │
                                                      ▼       ▼              ▼              ▼
                                                   Postgres  Postgres      Postgres      Postgres
                                                   (per service, AES-XTS-256 LUKS + KMS-CMK)
                                                      │
                                                      ▼
                                                   Kafka (audit) ── ClickHouse ── S3 (retention 365d)
                                                      │
                                                      ▼
                                                   HSM (PKCS#11, JWKS / SAML keys)
```

Each arrow represents a trust boundary. Below: STRIDE analysis per component.

---

## kacho-iam (IAM service: Account, Project, User, ServiceAccount, Group, Role, AccessBinding)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Attacker forges JWT to impersonate user | DPoP-bound tokens + RS256/ES256 signature verify against JWKS in HSM; mTLS Cilium for internal | Phase 2 + 10 |
| **Spoofing** | Service-to-service spoofing | SPIFFE SVID mTLS; CiliumNetworkPolicy with L7 SVID match | Phase 10 |
| **Tampering** | Modify AccessBinding to escalate privilege | Atomic CAS UPDATE; UNIQUE constraint on (subject, role, resource); audit pipeline append-only | Phase 1 + 9 |
| **Tampering** | Tamper system-role permission JSON | DB CHECK constraint `iam_permissions_valid`; CSPRNG-derived row IDs; audit log of role mutations | Phase 1 |
| **Repudiation** | Operator denies privilege change | Audit pipeline (Kafka → ClickHouse → S3) with Merkle batch hash; signed by audit-key | Phase 9 |
| **Information Disclosure** | Enumerate users via timing attack | Const-time HMAC compare; Kratos rate-limit; ZK-style "user not found OR password incorrect" | Phase 2 |
| **Information Disclosure** | Leak permission via Check error | OPA returns `permitted: false` w/o details; INFO-level log strips sensitive context | Phase 3 |
| **Denial of Service** | Flood Check RPC | Envoy local_rate_limit + Cloudflare WAF; FGA Check response caching (5s) | Phase 11 |
| **Denial of Service** | OpenFGA tuple-storage exhaustion | Per-tenant quota (Phase 7); circuit-breaker on Check failures | Phase 7 |
| **Elevation of Privilege** | Modify role assignments via SQLi | sqlc-gen parameterized queries (ORM banned, запрет #3) | Phase 1 |
| **Elevation of Privilege** | Privilege escalation via mass-assignment | Update-mask discipline; immutable fields enforced server-side | Phase 1 |

---

## kacho-api-gateway

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Forge `X-Kacho-Principal-*` headers | api-gateway strips client-supplied headers (CRIT-8 KAC-122 fix); identity from verified JWT only | Phase 2 |
| **Spoofing** | Replay DPoP proof | jti cache LRU-100k TTL 120s (RFC 9449 §11.1) | Phase 2 |
| **Spoofing** | mTLS bypass | Envoy `require_client_certificate: true` + SPIFFE SVID match | Phase 10 |
| **Tampering** | Modify request body in transit | TLS 1.3 + DPoP proof binds htm/htu/iat | Phase 2 |
| **Repudiation** | Deny request was sent | Audit log includes DPoP jti + request-hash | Phase 9 |
| **Information Disclosure** | Token leak in logs | Authorization header redacted in middleware; no plaintext token in OTel | Phase 2 |
| **Information Disclosure** | Stack trace leak | grpc-gateway strips stack in prod; recover-interceptor returns generic 500 | Phase 1 |
| **Denial of Service** | Slowloris / connection exhaustion | Envoy connection-buffer-size + max-connections + idle-timeout | Phase 11 |
| **Denial of Service** | Large request body | gRPC max-msg-size 4MB; REST max-body 1MB | Phase 1 |
| **Elevation of Privilege** | Bypass authorization middleware | Per-RPC FGA Check after parse; no admin-bypass paths | Phase 3 |

---

## Kratos (identity provider)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Account takeover via password reset | Magic-link 15min TTL; verified-email-only; rate-limit | Phase 2 |
| **Spoofing** | Phishing → WebAuthn | WebAuthn origin-binding + attestation FIDO MDS validation (impersonation-resistant) | Phase 2 |
| **Spoofing** | TOTP replay | TOTP HMAC-SHA256 + skew window 30s + state-tracking | Phase 2 |
| **Tampering** | Modify identity-trait JSON | Postgres CHECK constraint on identity_schema + admin-API only | Phase 2 |
| **Repudiation** | Deny session login | Kratos selfservice flow logs to audit-Kafka with WebAuthn challenge ID | Phase 2 + 9 |
| **Information Disclosure** | Identity enumeration | "no user found" returns same shape as "invalid credentials" | Phase 2 |
| **Information Disclosure** | Password hash leak | Argon2id with HSM-pepper; pg_dump excludes credentials_config | Phase 6 |
| **Denial of Service** | Brute force | Kratos lockout-after-5 + Cloudflare turnstile | Phase 11 |
| **Elevation of Privilege** | Self-service flow abuse | Each flow has CSRF token + state binding + IP rate-limit | Phase 2 |

---

## Hydra (OAuth2 / OIDC issuer)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Stolen authorization code | PKCE S256 mandatory; code-binding to PKCE-verifier | Phase 2 |
| **Spoofing** | Token theft replay | DPoP-bound tokens; mTLS-bound `cnf` claim | Phase 2 |
| **Tampering** | Token tampering | JWT signed RS256/ES256 from JWKS-HSM | Phase 2 |
| **Repudiation** | Deny token-issuance | Audit log every token-issuance with kid+iss+jti | Phase 9 |
| **Information Disclosure** | Token introspection leak | Introspection requires mTLS client cred | Phase 2 |
| **Information Disclosure** | JWKS key extraction | Private key in HSM only (PKCS#11); public via /jwks.json | Phase 11 |
| **Denial of Service** | Token-issuance flood | Per-client rate-limit + circuit-breaker | Phase 11 |
| **Elevation of Privilege** | Scope-creep | Hydra scope-policy strict-deny if not in whitelist | Phase 2 |
| **Elevation of Privilege** | Refresh-token reuse | Single-use refresh + rotation + family-detection | Phase 2 |

---

## OpenFGA (authorization)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Forge Check request | mTLS-only API; SPIFFE SVID required | Phase 3 + 10 |
| **Tampering** | Modify authorization model | Model deploys via GitOps (Argo CD); model-id versioned in Secret | Phase 11 |
| **Tampering** | Inject malicious tuples | Tuple writes only via kacho-iam (sole writer); idempotent on AccessBinding | Phase 3 |
| **Repudiation** | Deny tuple was added | Audit log on every tuple write | Phase 9 |
| **Information Disclosure** | Cross-tenant tuple leak | Per-tenant store-id; tenant-interceptor scopes Check | Phase 3 |
| **Denial of Service** | Check storm | Caching layer 5s TTL; circuit-breaker; gradual degradation to "deny" | Phase 3 |
| **Elevation of Privilege** | Misconfigured model | Authz model GitOps + PR review + ConformanceTest schema-validation | Phase 11 |

---

## Kafka (audit pipeline backbone)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Inject fake audit-event | Kafka SASL_SSL + ACL per-topic; signed SET events | Phase 8 + 9 |
| **Tampering** | Modify audit-log retroactively | Append-only topic + Merkle batch hash chain (every 5min) + verifier nightly | Phase 9 |
| **Repudiation** | Deny event was produced | Signed events; producer-id in event metadata | Phase 9 |
| **Information Disclosure** | Audit-log leak via consumer | ACL per-consumer-group; encryption at rest (Kafka SASL_SSL + KMS-CMK) | Phase 9 |
| **Denial of Service** | Disk-fill | Per-topic retention; quota + max-bytes; ClickHouse drain | Phase 9 |
| **Elevation of Privilege** | Consume cross-tenant audit | Per-tenant prefix in topic-name; ACL enforces tenant-scope | Phase 9 |

---

## ClickHouse (audit query / SIEM consumer)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Information Disclosure** | SQL injection via query | Parameterized queries (clickhouse-go driver) | Phase 9 |
| **Information Disclosure** | Read other tenants' audit | Row-level security via ClickHouse policy on `tenant_id` column | Phase 9 |
| **Tampering** | TTL/drop-table abuse | Read-only user for SIEM; admin requires break-glass 2-approve | Phase 9 |
| **Denial of Service** | Resource exhaustion query | Resource quota per-user + max-execution-time | Phase 11 |

---

## HSM (PKCS#11)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Unauthorized PKCS#11 session | mTLS to HSM endpoint + PIN from external-secrets | Phase 11 |
| **Tampering** | Key replacement | HSM partitions + write-once for production keys | Phase 11 |
| **Information Disclosure** | Key extraction | FIPS 140-2 L3 HSM; key marked `non-extractable` | Phase 11 |
| **Denial of Service** | Block legitimate signing | Multi-region HSM + automatic failover; secondary local-key as backup | Phase 12 chaos test |
| **Elevation of Privilege** | Cross-tenant key access | HSM partition per-tenant; SPIFFE SVID auth | Phase 11 |

---

## SPIRE (workload identity)

| Threat | Description | Mitigation | Phase |
|--------|-------------|------------|-------|
| **Spoofing** | Attest forged workload | Multi-factor selector (k8s NS + SA + UID + image-hash) | Phase 10 |
| **Tampering** | Modify trust bundle | trust-bundle signed by SPIRE-server CA; ratified by GitOps | Phase 10 |
| **Information Disclosure** | SVID leak | Short-lived SVID (1h TTL) + ephemeral; private key in pod-RAM only | Phase 10 |
| **Denial of Service** | Spam SVID requests | Per-workload quota | Phase 10 |
| **Elevation of Privilege** | SVID misuse cross-namespace | Cilium L7 SVID-match policy per-RPC | Phase 10 |

---

## Cross-cutting threats

### Quantum compute (post-quantum readiness)

- **Threat**: future quantum adversary breaks current RSA/ECDSA
- **Mitigation**: hybrid TLS plan (`docs/security/post-quantum-readiness.md`); crypto-agility one-config swap via Hydra `signing_alg`; JWKS rotation 90d limits exposure window
- **Phase**: Phase 12 documented; activation Phase 13+ (gated on browser-support of `ML-KEM` / `ML-DSA`)

### Supply chain compromise

- **Threat**: malicious dependency injected
- **Mitigation**: SBOM via syft per image; trivy/grype/gosec gates in CI; cosign signed images verified by Phase 11 admission policy
- **Phase**: Phase 11 + Phase 12 strict mode

### Insider threat (admin abuse)

- **Threat**: privileged operator exfiltrates data or escalates
- **Mitigation**: break-glass 2-approve (Phase 7); audit pipeline immutable + Merkle chain (Phase 9); MFA ACR=aal3 on admin actions (Phase 4); JIT/PIM (Phase 7)

### Tenant isolation breach

- **Threat**: tenant A reads tenant B data
- **Mitigation**:
  - per-service DB (запрет #8) — no SQL-injection cross-DB possible
  - tenant interceptor enforces `tenant_id` filter on every query
  - OpenFGA Check ensures `relation:owner` matches subject
  - audit pipeline tenant-id prefix; ClickHouse RLS

### Time-of-check time-of-use (TOCTOU)

- **Threat**: race between authorization-check and resource-write
- **Mitigation**: DB-level invariants (запрет #10) — atomic CAS / UNIQUE / EXCLUDE only; integration concurrent_race_test.go for every RPC; service-layer software-refcheck banned

---

## Verification

- ASVS L3 self-assessment: `asvs-l3-self-assessment.md`
- Conformance status: `conformance-status.md`
- Pentest readiness: `pentest-readiness.md`
- Litmus chaos experiments verify resilience claims: `helm/umbrella/charts/litmus-chaos/`

## References

- STRIDE: https://en.wikipedia.org/wiki/STRIDE_(security)
- ASVS V1.1.4: requires threat models per design change
- NIST SP 800-154 (Data-Centric System Threat Modeling)
