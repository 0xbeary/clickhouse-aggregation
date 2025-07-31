#!/bin/bash

# Multi-Indexer Analytics Pipeline Management Script

set -e

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

# Create shared network if it doesn't exist
create_network() {
    print_step "Creating shared network 'squid-network'"
    if docker network ls | grep -q squid-network; then
        print_warning "Network 'squid-network' already exists"
    else
        docker network create squid-network
        print_success "Network 'squid-network' created"
    fi
}

# Start core infrastructure (PostgreSQL + ClickHouse)
start_infrastructure() {
    print_step "Starting core infrastructure..."
    create_network
    
    print_step "Starting ClickHouse Analytics Database"
    docker-compose -f docker-compose.clickhouse.yml up -d
    
    print_step "Starting PostgreSQL Database"
    docker-compose -f docker-compose.postgres.yml up -d
    
    print_success "Core infrastructure started"
}

# Stop core infrastructure
stop_infrastructure() {
    print_step "Stopping core infrastructure..."
    docker-compose -f docker-compose.postgres.yml down
    docker-compose -f docker-compose.clickhouse.yml down
    print_success "Core infrastructure stopped"
}

# Add a new indexer to ClickHouse (while running)
add_indexer() {
    local db_name=$1
    local pg_host=${2:-"squid_postgres"}
    local pg_port=${3:-"5432"}
    local pg_user=${4:-"postgres"}
    local pg_pass=${5:-"postgres"}
    
    if [ -z "$db_name" ]; then
        print_error "Usage: add_indexer <database_name> [pg_host] [pg_port] [pg_user] [pg_pass]"
        exit 1
    fi
    
    print_step "Adding new indexer database: $db_name"
    
    # Check if ClickHouse is running
    if ! docker ps | grep -q squid_clickhouse_analytics; then
        print_error "ClickHouse is not running. Start infrastructure first."
        exit 1
    fi
    
    # Create materialized database in ClickHouse
    print_step "Creating MaterializedPostgreSQL database: $db_name"
    docker exec squid_clickhouse_analytics clickhouse-client --query "
        SET allow_experimental_database_materialized_postgresql = 1; 
        CREATE DATABASE IF NOT EXISTS ${db_name}_blockchain 
        ENGINE = MaterializedPostgreSQL('${pg_host}:${pg_port}', '${db_name}', '${pg_user}', '${pg_pass}');
    "
    
    # Create analytics database
    print_step "Creating analytics database: ${db_name}_analytics"
    docker exec squid_clickhouse_analytics clickhouse-client --query "
        CREATE DATABASE IF NOT EXISTS ${db_name}_analytics;
    "
    
    print_success "Indexer '$db_name' added successfully!"
    print_step "Data from PostgreSQL database '$db_name' will now replicate to:"
    echo "  - ${db_name}_blockchain (raw replicated tables)"
    echo "  - ${db_name}_analytics (for materialized views)"
}

# Remove an indexer from ClickHouse
remove_indexer() {
    local db_name=$1
    
    if [ -z "$db_name" ]; then
        print_error "Usage: remove_indexer <database_name>"
        exit 1
    fi
    
    print_step "Removing indexer database: $db_name"
    
    docker exec squid_clickhouse_analytics clickhouse-client --query "
        DROP DATABASE IF EXISTS ${db_name}_blockchain;
        DROP DATABASE IF EXISTS ${db_name}_analytics;
    "
    
    print_success "Indexer '$db_name' removed successfully!"
}

# List all indexers
list_indexers() {
    print_step "Current ClickHouse databases:"
    docker exec squid_clickhouse_analytics clickhouse-client --query "SHOW DATABASES;"
}

# Monitor replication status
monitor_replication() {
    local db_name=${1:-"all"}
    
    print_step "Replication status for: $db_name"
    
    if [ "$db_name" = "all" ]; then
        docker exec squid_clickhouse_analytics clickhouse-client --query "
            SELECT database, engine 
            FROM system.databases 
            WHERE engine LIKE '%MaterializedPostgreSQL%';
        "
    else
        docker exec squid_clickhouse_analytics clickhouse-client --query "
            SELECT database, engine 
            FROM system.databases 
            WHERE database = '${db_name}_blockchain';
        "
    fi
}

# Show usage
show_usage() {
    echo "Multi-Indexer Analytics Pipeline Management"
    echo "=========================================="
    echo ""
    echo "Infrastructure Management:"
    echo "  $0 start                           - Start ClickHouse + PostgreSQL"
    echo "  $0 stop                            - Stop all services"
    echo "  $0 network                         - Create shared network only"
    echo ""
    echo "Indexer Management (while running):"
    echo "  $0 add <db_name>                   - Add new indexer for database"
    echo "  $0 add <db_name> <host> <port>     - Add indexer with custom PostgreSQL"
    echo "  $0 remove <db_name>                - Remove indexer database"
    echo "  $0 list                            - List all indexer databases"
    echo "  $0 monitor [db_name]               - Monitor replication status"
    echo ""
    echo "Examples:"
    echo "  $0 start                           # Start infrastructure"
    echo "  $0 add usdctransfers               # Add USDC indexer"
    echo "  $0 add defi_protocol               # Add DeFi protocol indexer"
    echo "  $0 add nft_marketplace             # Add NFT marketplace indexer"
    echo "  $0 monitor usdctransfers           # Monitor USDC replication"
}

# Main script logic
case "$1" in
    "start")
        start_infrastructure
        ;;
    "stop")
        stop_infrastructure
        ;;
    "network")
        create_network
        ;;
    "add")
        add_indexer "$2" "$3" "$4" "$5" "$6"
        ;;
    "remove")
        remove_indexer "$2"
        ;;
    "list")
        list_indexers
        ;;
    "monitor")
        monitor_replication "$2"
        ;;
    *)
        show_usage
        ;;
esac
