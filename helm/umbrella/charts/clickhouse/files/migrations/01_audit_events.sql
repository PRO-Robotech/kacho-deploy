-- KAC-127 Phase 9 — ClickHouse schema initialization for kacho-iam audit events.
-- Соответствует acceptance §2.6 (нормативно).
--
-- Применяется schema-init Job'ом после поднятия ClickHouse cluster.
-- Idempotent — IF NOT EXISTS на всех CREATE'ах.

CREATE DATABASE IF NOT EXISTS kacho_audit
ON CLUSTER 'kacho_audit';

-- ─── audit_events_local (one per shard, Replicated) ─────────────────────
CREATE TABLE IF NOT EXISTS kacho_audit.audit_events_local ON CLUSTER 'kacho_audit'
(
    event_id            String,
    event_type          LowCardinality(String),
    timestamp           DateTime64(3, 'UTC'),
    tenant_account_id   String,
    tenant_org_id       String,
    actor_id            String,
    actor_type          LowCardinality(String),
    actor_ip            String,
    target_id           String,
    target_type         LowCardinality(String),
    action              LowCardinality(String),
    outcome             LowCardinality(String),
    request_id          String,
    operation_id        String,
    -- Full CADF payload — JSON forensic.
    payload             String CODEC(ZSTD(3)),
    -- Risk signals (extracted for fast indexing).
    risk_anomaly_score  Float32,
    risk_impossible_travel UInt8,
    -- Ingestion metadata.
    ingested_at         DateTime64(3, 'UTC') DEFAULT now64(3),

    -- Indexes для частых query patterns.
    INDEX idx_actor_id actor_id TYPE bloom_filter(0.01) GRANULARITY 8,
    INDEX idx_target_id target_id TYPE bloom_filter(0.01) GRANULARITY 8,
    INDEX idx_request_id request_id TYPE bloom_filter(0.01) GRANULARITY 8
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/audit_events_local', '{replica}')
PARTITION BY (tenant_account_id, toDate(timestamp))
ORDER BY (tenant_account_id, timestamp, event_id)
TTL toDate(timestamp) + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;

-- ─── Distributed table — query entrypoint ───────────────────────────────
CREATE TABLE IF NOT EXISTS kacho_audit.audit_events ON CLUSTER 'kacho_audit'
AS kacho_audit.audit_events_local
ENGINE = Distributed('kacho_audit', kacho_audit, audit_events_local, sipHash64(tenant_account_id));

-- ─── audit_events_merkle — Merkle chain root storage ────────────────────
-- Mirror Postgres `audit_signing_batches` table; redundant copy в OLAP layer
-- для быстрого forensic query "найди batch_id по event_id range".
CREATE TABLE IF NOT EXISTS kacho_audit.audit_events_merkle_local ON CLUSTER 'kacho_audit'
(
    batch_id            String,
    batch_seq           UInt64,
    batch_hash          String,
    previous_batch_hash String,
    merkle_root         String,
    event_count         UInt32,
    event_id_min        String,
    event_id_max        String,
    window_started_at   DateTime64(3, 'UTC'),
    window_ended_at     DateTime64(3, 'UTC'),
    signing_key_id      LowCardinality(String),
    signing_algorithm   LowCardinality(String),
    signature_b64       String,
    s3_uri              String,
    s3_manifest_uri     String,
    verifier_status     LowCardinality(String),
    verified_at         Nullable(DateTime64(3, 'UTC')),
    signed_at           DateTime64(3, 'UTC')
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/audit_events_merkle_local', '{replica}')
PARTITION BY toYYYYMM(signed_at)
ORDER BY (batch_seq, batch_id)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS kacho_audit.audit_events_merkle ON CLUSTER 'kacho_audit'
AS kacho_audit.audit_events_merkle_local
ENGINE = Distributed('kacho_audit', kacho_audit, audit_events_merkle_local, sipHash64(batch_id));

-- ─── audit_verifier_results — daily verifier run output ────────────────
CREATE TABLE IF NOT EXISTS kacho_audit.audit_verifier_results_local ON CLUSTER 'kacho_audit'
(
    run_id              String,
    run_started_at      DateTime64(3, 'UTC'),
    run_ended_at        DateTime64(3, 'UTC'),
    batches_walked      UInt64,
    signatures_verified UInt64,
    chain_links_verified UInt64,
    s3_objects_verified UInt64,
    anomalies_found     UInt32,
    anomaly_batch_ids   Array(String),
    status              LowCardinality(String),
    pagerduty_incident_key Nullable(String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/audit_verifier_results_local', '{replica}')
PARTITION BY toYYYYMM(run_started_at)
ORDER BY (run_started_at, run_id)
TTL toDate(run_started_at) + INTERVAL 7 YEAR DELETE
SETTINGS index_granularity = 1024;

CREATE TABLE IF NOT EXISTS kacho_audit.audit_verifier_results ON CLUSTER 'kacho_audit'
AS kacho_audit.audit_verifier_results_local
ENGINE = Distributed('kacho_audit', kacho_audit, audit_verifier_results_local, rand());
