-- KAC-127 Phase 9 — ClickHouse Kafka engine consumer (P9-D22 / P9-D23).
-- Применяется после 01_audit_events.sql.
--
-- Параметры подставляются на render-time (см. schema-init-job.yaml env).

-- Kafka engine consumer table — НЕ хранит данные, только consumes.
CREATE TABLE IF NOT EXISTS kacho_audit.audit_events_kafka ON CLUSTER 'kacho_audit'
(
    -- Минимальный set колонок parsed-from-Kafka; full payload передаётся как String.
    -- MaterializedView ниже разбирает JSON и пишет в audit_events_local.
    raw_message String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = '${KAFKA_BOOTSTRAP_SERVERS}',
    kafka_topic_list = '${KAFKA_TOPIC}',
    kafka_group_name = '${KAFKA_CONSUMER_GROUP}',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 4,
    kafka_max_block_size = ${KAFKA_MAX_BLOCK_SIZE},
    kafka_flush_interval_ms = ${KAFKA_FLUSH_INTERVAL_MS},
    kafka_handle_error_mode = 'stream',
    kafka_security_protocol = 'SASL_SSL',
    kafka_sasl_mechanism = 'SCRAM-SHA-512',
    kafka_sasl_username = '${KAFKA_SASL_USERNAME}',
    kafka_sasl_password = '${KAFKA_SASL_PASSWORD}',
    kafka_ssl_ca_location = '/etc/clickhouse-server/kafka-tls/ca.crt';

-- MaterializedView — pulls from Kafka, parses CADF JSON, INSERT'ит в audit_events_local.
CREATE MATERIALIZED VIEW IF NOT EXISTS kacho_audit.audit_events_kafka_mv ON CLUSTER 'kacho_audit'
TO kacho_audit.audit_events_local AS
SELECT
    JSONExtractString(raw_message, 'event_id')        AS event_id,
    JSONExtractString(raw_message, 'event_type')      AS event_type,
    parseDateTime64BestEffortOrNull(JSONExtractString(raw_message, 'timestamp'), 3) AS timestamp,
    JSONExtractString(raw_message, 'tenant', 'account_id')      AS tenant_account_id,
    JSONExtractString(raw_message, 'tenant', 'organization_id') AS tenant_org_id,
    JSONExtractString(raw_message, 'actor', 'id')               AS actor_id,
    JSONExtractString(raw_message, 'actor', 'type')             AS actor_type,
    JSONExtractString(raw_message, 'actor', 'ip')               AS actor_ip,
    JSONExtractString(raw_message, 'target', 'id')              AS target_id,
    JSONExtractString(raw_message, 'target', 'type')            AS target_type,
    JSONExtractString(raw_message, 'action')                    AS action,
    JSONExtractString(raw_message, 'outcome')                   AS outcome,
    JSONExtractString(raw_message, 'request', 'request_id')     AS request_id,
    JSONExtractString(raw_message, 'response', 'operation_id')  AS operation_id,
    raw_message                                                 AS payload,
    JSONExtractFloat(raw_message, 'risk_signals', 'anomaly_score')                AS risk_anomaly_score,
    JSONExtractUInt(raw_message, 'risk_signals', 'impossible_travel')             AS risk_impossible_travel,
    now64(3)                                                                       AS ingested_at
FROM kacho_audit.audit_events_kafka;

-- ─── Aggregation MVs (per-actor / per-resource counters) ───────────────
-- SOC2-friendly real-time aggregations: для UI Activity tab.

CREATE TABLE IF NOT EXISTS kacho_audit.audit_actor_counters_local ON CLUSTER 'kacho_audit'
(
    tenant_account_id String,
    actor_id          String,
    day               Date,
    event_count       UInt64,
    success_count     UInt64,
    failure_count     UInt64
)
ENGINE = SummingMergeTree(event_count, success_count, failure_count)
PARTITION BY toYYYYMM(day)
ORDER BY (tenant_account_id, actor_id, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS kacho_audit.audit_actor_counters_mv ON CLUSTER 'kacho_audit'
TO kacho_audit.audit_actor_counters_local AS
SELECT
    tenant_account_id,
    actor_id,
    toDate(timestamp) AS day,
    count() AS event_count,
    countIf(outcome = 'success') AS success_count,
    countIf(outcome = 'failure') AS failure_count
FROM kacho_audit.audit_events_local
GROUP BY tenant_account_id, actor_id, day;
