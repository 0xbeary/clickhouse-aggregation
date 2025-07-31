#!/bin/bash

# USDC Transfer Pipeline Configuration Script
# This script configures PostgreSQL and ClickHouse for real-time replication

set -e

echo "🚀 Configuring USDC Transfer Pipeline with PostgreSQL → ClickHouse Replication"
echo "=================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}📋 Step $1: $2${NC}"
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

# Step 1: Start services
print_step "1" "Starting PostgreSQL and ClickHouse services"
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 5

# Check if services are running
print_step "2" "Verifying services are running"
if docker-compose ps | grep -q "Up"; then
    print_success "Services are running"
    docker-compose ps
else
    print_error "Services failed to start"
    exit 1
fi

# Step 3: Configure PostgreSQL for logical replication
print_step "3" "Configuring PostgreSQL for logical replication"

echo "Setting WAL level to logical..."
docker-compose exec -T db psql -U postgres -d usdctransfers -c "ALTER SYSTEM SET wal_level = 'logical';"

echo "Setting max replication slots..."
docker-compose exec -T db psql -U postgres -d usdctransfers -c "ALTER SYSTEM SET max_replication_slots = 2;"

echo "Reloading PostgreSQL configuration..."
docker-compose exec -T db psql -U postgres -d usdctransfers -c "SELECT pg_reload_conf();"

print_success "PostgreSQL configuration updated"

# Step 4: Restart PostgreSQL for WAL level changes
print_step "4" "Restarting PostgreSQL to apply WAL level changes"
docker-compose restart db

echo "Waiting for PostgreSQL to restart..."
sleep 3

# Verify WAL level
echo "Verifying WAL level..."
WAL_LEVEL=$(docker-compose exec -T db psql -U postgres -d usdctransfers -t -c "SHOW wal_level;" | xargs)
if [ "$WAL_LEVEL" = "logical" ]; then
    print_success "WAL level is set to logical"
else
    print_error "WAL level is not set correctly: $WAL_LEVEL"
    exit 1
fi

# Step 5: Create publication
print_step "5" "Creating PostgreSQL publication"
docker-compose exec -T db psql -U postgres -d usdctransfers -c "CREATE PUBLICATION usdc_pub FOR ALL TABLES;"
print_success "Publication 'usdc_pub' created for all tables"

# Step 6: Configure ClickHouse
print_step "6" "Configuring ClickHouse for MaterializedPostgreSQL"

echo "Creating blockchain database with MaterializedPostgreSQL engine..."
docker-compose exec -T clickhouse clickhouse-client --query "SET allow_experimental_database_materialized_postgresql = 1; CREATE DATABASE blockchain ENGINE = MaterializedPostgreSQL('db:5432', 'usdctransfers', 'postgres', 'postgres');"

echo "Creating analytics database for materialized views..."
docker-compose exec -T clickhouse clickhouse-client --query "CREATE DATABASE analytics;"

print_success "ClickHouse databases created"

# Step 7: Verify setup
print_step "7" "Verifying setup"

echo "PostgreSQL databases:"
docker-compose exec -T db psql -U postgres -l

echo ""
echo "ClickHouse databases:"
docker-compose exec -T clickhouse clickhouse-client --query "SHOW DATABASES;"

echo ""
echo "PostgreSQL publications:"
docker-compose exec -T db psql -U postgres -d usdctransfers -c "SELECT pubname FROM pg_publication;"

echo ""
echo "PostgreSQL replication slots (will be created when ClickHouse connects):"
docker-compose exec -T db psql -U postgres -d usdctransfers -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"

print_success "Setup verification complete"

echo ""
echo "=================================================================="
echo -e "${GREEN}🎉 PostgreSQL → ClickHouse replication pipeline configured successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Run 'sqd process' to start the USDC transfer processor"
echo "2. The processor will create the usdc_transfer table in PostgreSQL"
echo "3. ClickHouse will automatically replicate the table to blockchain.usdc_transfer"
echo "4. Create materialized views in the analytics database for fast queries"
echo ""
echo "Monitor replication:"
echo "- PostgreSQL: docker-compose exec db psql -U postgres -d usdctransfers -c \"SELECT * FROM pg_replication_slots;\""
echo "- ClickHouse: docker-compose exec clickhouse clickhouse-client --query \"SELECT * FROM system.replication_queue WHERE database = 'blockchain';\""
