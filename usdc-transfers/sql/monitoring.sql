-- ClickHouse Monitoring Queries
-- Run individual queries to monitor replication and performance

-- Check replication status
SELECT 
    database,
    table,
    latest_successful_update_time,
    latest_failed_update_time,
    consecutive_successful_updates,
    consecutive_failed_updates
FROM system.materialized_postgresql_tables
WHERE database = 'blockchain';

-- Check ClickHouse replication queue
SELECT *
FROM system.replication_queue
WHERE database = 'blockchain';

-- Check table sizes
SELECT 
    database,
    table,
    formatReadableSize(total_bytes) AS size,
    rows,
    days
FROM system.tables 
WHERE database IN ('blockchain', 'analytics')
ORDER BY total_bytes DESC;

-- Check recent data in blockchain.usdc_transfer (if table exists)
SELECT 
    count() as total_rows,
    min(block_timestamp) as earliest_block,
    max(block_timestamp) as latest_block,
    sum(value) as total_volume
FROM blockchain.usdc_transfer
WHERE _sign = 1;

-- Sample recent transfers
SELECT 
    block_timestamp,
    from_address,
    to_address,
    value,
    transaction_hash
FROM blockchain.usdc_transfer
WHERE _sign = 1
ORDER BY block_timestamp DESC
LIMIT 10;
