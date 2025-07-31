-- PostgreSQL Performance Optimizations for Large Tables
-- These can be applied immediately without downtime

-- 1. Optimize PostgreSQL configuration for large datasets
-- Run these to improve write performance

-- Increase checkpoint completion target for smoother writes
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- Increase WAL buffers for better write performance
ALTER SYSTEM SET wal_buffers = '128MB';

-- Increase shared buffers (set to 25% of available RAM)
ALTER SYSTEM SET shared_buffers = '1GB';

-- Increase effective cache size (set to 75% of available RAM)
ALTER SYSTEM SET effective_cache_size = '3GB';

-- Increase work memory for sorting operations
ALTER SYSTEM SET work_mem = '256MB';

-- Increase maintenance work memory for index operations
ALTER SYSTEM SET maintenance_work_mem = '512MB';

-- Enable parallel workers for queries
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 8;

-- Optimize for write-heavy workloads
ALTER SYSTEM SET synchronous_commit = off;  -- Be careful with this!
ALTER SYSTEM SET commit_delay = 100000;     -- Microseconds
ALTER SYSTEM SET commit_siblings = 10;

-- Reload configuration
SELECT pg_reload_conf();

-- 2. Optimize specific table settings
-- Reduce table bloat with more aggressive autovacuum
ALTER TABLE usdc_transfer SET (
    autovacuum_vacuum_scale_factor = 0.05,    -- Vacuum when 5% of table changes
    autovacuum_analyze_scale_factor = 0.05,   -- Analyze when 5% of table changes
    autovacuum_vacuum_cost_delay = 10,        -- Faster vacuum
    autovacuum_vacuum_cost_limit = 2000       -- Higher vacuum cost limit
);

-- 3. Create additional optimized indexes for common queries
-- Index for recent block queries (most common pattern)
CREATE INDEX CONCURRENTLY idx_usdc_transfer_block_desc ON usdc_transfer (block DESC);

-- Partial index for high-value transactions (if needed for analytics)
CREATE INDEX CONCURRENTLY idx_usdc_transfer_high_value 
ON usdc_transfer (block, value) 
WHERE value > 1000000000;  -- > $1000 USDC

-- Composite index for address + block queries
CREATE INDEX CONCURRENTLY idx_usdc_transfer_from_block 
ON usdc_transfer ("from", block DESC);

CREATE INDEX CONCURRENTLY idx_usdc_transfer_to_block 
ON usdc_transfer ("to", block DESC);

-- 4. Analyze tables to update statistics
ANALYZE usdc_transfer;
