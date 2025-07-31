-- PostgreSQL Partitioning Setup for USDC Transfers
-- This will dramatically improve performance for large tables

-- 1. Create new partitioned table structure
CREATE TABLE usdc_transfer_partitioned (
    id character varying NOT NULL,
    block integer NOT NULL,
    "from" text NOT NULL,
    "to" text NOT NULL,
    value numeric NOT NULL,
    txn_hash text NOT NULL
) PARTITION BY RANGE (block);

-- 2. Create partitions for every 1 million blocks (adjust based on your data)
-- Current blocks are around 13M, so create partitions from 6M to 25M

CREATE TABLE usdc_transfer_p6m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (6000000) TO (7000000);

CREATE TABLE usdc_transfer_p7m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (7000000) TO (8000000);

CREATE TABLE usdc_transfer_p8m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (8000000) TO (9000000);

CREATE TABLE usdc_transfer_p9m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (9000000) TO (10000000);

CREATE TABLE usdc_transfer_p10m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (10000000) TO (11000000);

CREATE TABLE usdc_transfer_p11m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (11000000) TO (12000000);

CREATE TABLE usdc_transfer_p12m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (12000000) TO (13000000);

CREATE TABLE usdc_transfer_p13m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (13000000) TO (14000000);

CREATE TABLE usdc_transfer_p14m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (14000000) TO (15000000);

-- Create future partitions
CREATE TABLE usdc_transfer_p15m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (15000000) TO (16000000);

CREATE TABLE usdc_transfer_p16m PARTITION OF usdc_transfer_partitioned
    FOR VALUES FROM (16000000) TO (17000000);

-- Add more partitions as needed...

-- 3. Create indexes on partitioned table (will be created on all partitions)
CREATE UNIQUE INDEX idx_usdc_transfer_partitioned_pkey ON usdc_transfer_partitioned (id);
CREATE INDEX idx_usdc_transfer_partitioned_to ON usdc_transfer_partitioned ("to");
CREATE INDEX idx_usdc_transfer_partitioned_from ON usdc_transfer_partitioned ("from");
CREATE INDEX idx_usdc_transfer_partitioned_txn_hash ON usdc_transfer_partitioned (txn_hash);
CREATE INDEX idx_usdc_transfer_partitioned_block ON usdc_transfer_partitioned (block);

-- 4. Add constraint for performance (PostgreSQL can use this for partition pruning)
ALTER TABLE usdc_transfer_partitioned ADD CONSTRAINT chk_block_range 
    CHECK (block >= 6000000 AND block < 25000000);

-- 5. Migration script (run during maintenance window)
-- INSERT INTO usdc_transfer_partitioned SELECT * FROM usdc_transfer;
-- ALTER TABLE usdc_transfer RENAME TO usdc_transfer_old;
-- ALTER TABLE usdc_transfer_partitioned RENAME TO usdc_transfer;
