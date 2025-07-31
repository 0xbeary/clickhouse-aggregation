#!/bin/bash

# Analytics Setup Script
# Creates materialized views in ClickHouse for USDC transfer analytics

set -e

echo "📊 Setting up ClickHouse Analytics Materialized Views"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if usdc_transfer table exists
print_step "Checking if usdc_transfer table exists in ClickHouse..."

if docker-compose exec -T clickhouse clickhouse-client --query "EXISTS TABLE blockchain.usdc_transfer" | grep -q "1"; then
    print_success "usdc_transfer table found in ClickHouse"
else
    print_warning "usdc_transfer table not found. Make sure the Squid processor has run and created the table."
    echo "Run 'sqd process' first, then run this script again."
    exit 1
fi

# Create daily rollup materialized view
print_step "Creating daily USDC transfer rollup materialized view..."
docker-compose exec -T clickhouse clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_usdc_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(block_timestamp)
ORDER BY (from_address, to_address)
AS
SELECT
  from_address,
  to_address,
  sum(value) AS total_usdc,
  count() AS tx_count,
  toDate(block_timestamp) AS day
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY day, from_address, to_address;"

print_success "Daily rollup materialized view created"

# Create hourly volume materialized view
print_step "Creating hourly volume materialized view..."
docker-compose exec -T clickhouse clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_usdc_hourly
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(block_timestamp)
ORDER BY (hour)
AS
SELECT
  toStartOfHour(block_timestamp) AS hour,
  sum(value) AS total_volume,
  count() AS tx_count,
  uniq(from_address) AS unique_senders,
  uniq(to_address) AS unique_receivers
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY hour;"

print_success "Hourly volume materialized view created"

# Create top addresses materialized view
print_step "Creating top addresses materialized view..."
docker-compose exec -T clickhouse clickhouse-client --query "
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.mv_top_addresses
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(block_timestamp)
ORDER BY (address, address_type)
AS
SELECT
  from_address AS address,
  'sender' AS address_type,
  sum(value) AS volume,
  count() AS tx_count,
  toDate(block_timestamp) AS day
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY day, address

UNION ALL

SELECT
  to_address AS address,
  'receiver' AS address_type,
  sum(value) AS volume,
  count() AS tx_count,
  toDate(block_timestamp) AS day
FROM blockchain.usdc_transfer
WHERE _sign = 1
GROUP BY day, address;"

print_success "Top addresses materialized view created"

# Verify materialized views
print_step "Verifying materialized views..."
echo "Analytics database tables:"
docker-compose exec -T clickhouse clickhouse-client --query "SHOW TABLES FROM analytics;"

echo ""
echo "Sample queries:"
echo "==============="

echo "Daily volume (last 5 days):"
docker-compose exec -T clickhouse clickhouse-client --query "
SELECT 
  day,
  sum(total_usdc) as daily_volume,
  sum(tx_count) as daily_transactions
FROM analytics.mv_usdc_daily 
GROUP BY day 
ORDER BY day DESC 
LIMIT 5;" 2>/dev/null || echo "No data yet - start the processor to see results"

echo ""
echo "Hourly volume (last 24 hours):"
docker-compose exec -T clickhouse clickhouse-client --query "
SELECT 
  hour,
  total_volume,
  tx_count,
  unique_senders,
  unique_receivers
FROM analytics.mv_usdc_hourly 
ORDER BY hour DESC 
LIMIT 24;" 2>/dev/null || echo "No data yet - start the processor to see results"

echo ""
print_success "Analytics setup complete!"
echo ""
echo "Available materialized views:"
echo "- analytics.mv_usdc_daily: Daily transfer rollups by address pair"
echo "- analytics.mv_usdc_hourly: Hourly volume and transaction metrics"
echo "- analytics.mv_top_addresses: Top addresses by volume (senders/receivers)"
echo ""
echo "These views will automatically update as new data flows from PostgreSQL to ClickHouse."
