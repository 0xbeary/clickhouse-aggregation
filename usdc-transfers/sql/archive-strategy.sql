-- Archive Strategy for Large USDC Transfer Tables
-- This helps manage table growth over time

-- 1. Create archive table for old data
CREATE TABLE usdc_transfer_archive (
    LIKE usdc_transfer INCLUDING ALL
);

-- Add constraint to prevent accidental inserts
ALTER TABLE usdc_transfer_archive ADD CONSTRAINT chk_archive_blocks 
CHECK (block < 10000000);  -- Adjust based on your archival threshold

-- 2. Archive old data (example: archive blocks older than 3M blocks)
-- Run this periodically to move old data to archive table

-- Calculate archival threshold (keep last 3M blocks in main table)
DO $$
DECLARE
    max_block integer;
    archive_threshold integer;
BEGIN
    SELECT MAX(block) INTO max_block FROM usdc_transfer;
    archive_threshold := max_block - 3000000;  -- Keep last 3M blocks
    
    RAISE NOTICE 'Max block: %, Archive threshold: %', max_block, archive_threshold;
    
    -- Move old data to archive (uncomment when ready)
    -- INSERT INTO usdc_transfer_archive 
    -- SELECT * FROM usdc_transfer WHERE block < archive_threshold;
    
    -- Delete old data from main table (uncomment when ready)
    -- DELETE FROM usdc_transfer WHERE block < archive_threshold;
END $$;

-- 3. Create separate indexes on archive table
CREATE INDEX idx_usdc_transfer_archive_block ON usdc_transfer_archive (block);
CREATE INDEX idx_usdc_transfer_archive_from ON usdc_transfer_archive ("from");
CREATE INDEX idx_usdc_transfer_archive_to ON usdc_transfer_archive ("to");

-- 4. Create view that combines both tables for historical queries
CREATE VIEW usdc_transfer_complete AS
SELECT * FROM usdc_transfer_archive
UNION ALL
SELECT * FROM usdc_transfer;

-- 5. Automated archive function (call this periodically)
CREATE OR REPLACE FUNCTION archive_old_transfers()
RETURNS void AS $$
DECLARE
    max_block integer;
    archive_threshold integer;
    archived_count integer;
BEGIN
    SELECT MAX(block) INTO max_block FROM usdc_transfer;
    archive_threshold := max_block - 3000000;  -- Keep last 3M blocks
    
    -- Move old data to archive
    INSERT INTO usdc_transfer_archive 
    SELECT * FROM usdc_transfer WHERE block < archive_threshold;
    
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    
    -- Delete old data from main table
    DELETE FROM usdc_transfer WHERE block < archive_threshold;
    
    RAISE NOTICE 'Archived % rows with blocks < %', archived_count, archive_threshold;
    
    -- Update statistics
    ANALYZE usdc_transfer;
    ANALYZE usdc_transfer_archive;
END;
$$ LANGUAGE plpgsql;
