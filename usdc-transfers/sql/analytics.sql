-- ClickHouse Analytics SQL
-- This file contains SQL commands for creating materialized views and analytics queries
-- Run with: docker-compose exec clickhouse clickhouse-client --multiquery < sql/analytics.sql

-- Create analytics database
CREATE DATABASE IF NOT EXISTS analytics;

-- Daily USDC transfer rollup (using block number ranges)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_usdc_daily
ENGINE = SummingMergeTree()
PARTITION BY intDiv(block, 100000)  -- Partition by 100k block ranges
ORDER BY (from_address, to_address, block_range)
AS
SELECT
    from_address,
    to_address,
    sum(value) AS total_usdc,
    count() AS tx_count,
    intDiv(block, 7200) AS block_range  -- ~1 day = 7200 blocks
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY block_range, from_address, to_address;

-- Hourly USDC transfer volume (using block ranges)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_usdc_hourly
ENGINE = SummingMergeTree()
PARTITION BY intDiv(block, 50000)  -- Partition by 50k block ranges
ORDER BY block_hour
AS
SELECT
    intDiv(block, 300) AS block_hour,  -- ~1 hour = 300 blocks
    sum(value) AS total_volume,
    count() AS tx_count,
    uniq(from_address) AS unique_senders,
    uniq(to_address) AS unique_receivers
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY block_hour;

-- Top addresses by volume (senders)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_top_senders
ENGINE = SummingMergeTree()
PARTITION BY intDiv(block, 100000)  -- Partition by 100k block ranges
ORDER BY (from_address, block_range)
AS
SELECT
    from_address,
    sum(value) AS total_sent,
    count() AS tx_count,
    intDiv(block, 7200) AS block_range  -- ~1 day = 7200 blocks
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY block_range, from_address;

-- Top addresses by volume (receivers)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_top_receivers
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(block_timestamp)
ORDER BY (to_address, day)
AS
SELECT
    to_address,
    sum(value) AS total_received,
    count() AS tx_count,
    toDate(block_timestamp) AS day
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY day, to_address;

-- Transaction size distribution
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_tx_size_distribution
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(block_timestamp)
ORDER BY (size_bucket, day)
AS
SELECT
    multiIf(
        value < 100000000, 'small',      -- < $100
        value < 1000000000, 'medium',    -- $100 - $1,000
        value < 10000000000, 'large',    -- $1,000 - $10,000
        'whale'                          -- > $10,000
    ) AS size_bucket,
    count() AS tx_count,
    sum(value) AS total_volume,
    toDate(block_timestamp) AS day
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY day, size_bucket;

-- Real-time monitoring view (last 24 hours)
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_recent_activity
ENGINE = ReplacingMergeTree()
PARTITION BY toYYYYMMDD(block_timestamp)
ORDER BY (block_timestamp, transaction_hash, log_index)
AS
SELECT
    block_timestamp,
    transaction_hash,
    log_index,
    from_address,
    to_address,
    value,
    block_number
FROM blockchain.usdc_transfer
WHERE _sign = 1
AND block_timestamp >= now() - INTERVAL 24 HOUR;
