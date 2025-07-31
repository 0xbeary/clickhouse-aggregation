#!/bin/bash

# Enhanced Multi-Indexer Replication Configuration Script
# This script configures PostgreSQL and adds it to ClickHouse analytics pipeline

set -e

# Configuration
DB_NAME=${1:-"usdctransfers"}
PG_HOST=${2:-"squid_postgres"}
CH_HOST=${3:-"squid_clickhouse_analytics"}

echo "🚀 Configuring Multi-Indexer Analytics Pipeline"
echo "Database: $DB_NAME | PostgreSQL: $PG_HOST | ClickHouse: $CH_HOST"
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

# Step 1: Configure PostgreSQL for logical replication
print_step "1" "Configuring PostgreSQL for logical replication"

echo "Setting WAL level to logical..."
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "ALTER SYSTEM SET wal_level = 'logical';"

echo "Setting max replication slots..."
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "ALTER SYSTEM SET max_replication_slots = 10;"

echo "Setting max worker processes..."
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "ALTER SYSTEM SET max_worker_processes = 16;"

echo "Reloading PostgreSQL configuration..."
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "SELECT pg_reload_conf();"

print_success "PostgreSQL configuration updated"

# Step 2: Restart PostgreSQL for WAL level changes
print_step "2" "Restarting PostgreSQL to apply WAL level changes"
if [ -f "docker-compose.postgres.yml" ]; then
    docker-compose -f docker-compose.postgres.yml restart db
else
    docker restart $PG_HOST
fi

echo "Waiting for PostgreSQL to restart..."
sleep 5

# Verify WAL level
echo "Verifying WAL level..."
WAL_LEVEL=$(docker exec $PG_HOST psql -U postgres -d $DB_NAME -t -c "SHOW wal_level;" | xargs)
if [ "$WAL_LEVEL" = "logical" ]; then
    print_success "WAL level is set to logical"
else
    print_error "WAL level is not set correctly: $WAL_LEVEL"
    exit 1
fi

# Step 3: Create publication
print_step "3" "Creating PostgreSQL publication for $DB_NAME"
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "CREATE PUBLICATION ${DB_NAME}_pub FOR ALL TABLES;" || print_warning "Publication may already exist"
print_success "Publication '${DB_NAME}_pub' configured for all tables"

# Step 4: Add to ClickHouse analytics pipeline
print_step "4" "Adding $DB_NAME to ClickHouse analytics pipeline"

# Check if ClickHouse is running
if ! docker ps | grep -q $CH_HOST; then
    print_error "ClickHouse container '$CH_HOST' is not running"
    exit 1
fi

# Create materialized database
echo "Creating blockchain database with MaterializedPostgreSQL engine..."
docker exec $CH_HOST clickhouse-client --query "SET allow_experimental_database_materialized_postgresql = 1; CREATE DATABASE IF NOT EXISTS ${DB_NAME}_blockchain ENGINE = MaterializedPostgreSQL('$PG_HOST:5432', '$DB_NAME', 'postgres', 'postgres');"

echo "Creating analytics database for materialized views..."
docker exec $CH_HOST clickhouse-client --query "CREATE DATABASE IF NOT EXISTS ${DB_NAME}_analytics;"

print_success "ClickHouse databases created for $DB_NAME"

# Step 5: Verify setup
print_step "5" "Verifying setup for $DB_NAME"

echo "PostgreSQL databases:"
docker exec $PG_HOST psql -U postgres -l | grep $DB_NAME

echo ""
echo "ClickHouse databases:"
docker exec $CH_HOST clickhouse-client --query "SHOW DATABASES;" | grep $DB_NAME

echo ""
echo "PostgreSQL publications:"
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "SELECT pubname FROM pg_publication WHERE pubname LIKE '%${DB_NAME}%';"

echo ""
echo "PostgreSQL replication slots:"
docker exec $PG_HOST psql -U postgres -d $DB_NAME -c "SELECT slot_name, slot_type, active FROM pg_replication_slots WHERE slot_name LIKE '%${DB_NAME}%';"

print_success "Setup verification complete for $DB_NAME"

echo ""
echo "=================================================================="
echo -e "${GREEN}🎉 $DB_NAME added to analytics pipeline successfully!${NC}"
echo ""
echo "Data flow:"
echo "  PostgreSQL '$DB_NAME' → ClickHouse '${DB_NAME}_blockchain' (real-time replication)"
echo "  → ClickHouse '${DB_NAME}_analytics' (materialized views)"
echo ""
echo "Monitor replication:"
echo "  ./scripts/manage-analytics.sh monitor $DB_NAME"
echo ""
echo "Create analytics views:"
echo "  docker exec $CH_HOST clickhouse-client --query \"CREATE MATERIALIZED VIEW ${DB_NAME}_analytics.my_view ...\""
