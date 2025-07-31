# Showcase squid 01: USDC transfers in real time

This squid captures all `Transfer(address,address,uint256)` events emitted by the [USDC token contract](https://etherscan.io/address/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) and keeps up with network updates [in real time](https://docs.subsquid.io/basics/unfinalized-blocks/). See more examples of requesting data with squids on the [showcase page](https://docs.subsquid.io/evm-indexing/configuration/showcase) of Subsquid documentation.

This project includes **PostgreSQL to ClickHouse replication** for real-time analytics and high-performance queries.

Dependencies: Node.js, Docker.

## Quickstart

```bash
# 0. Install @subsquid/cli a.k.a. the sqd command globally
npm i -g @subsquid/cli

# 1. Retrieve the template
sqd init showcase01 -t https://github.com/subsquid-labs/showcase01-all-usdc-transfers
cd showcase01

# 2. Install dependencies
npm ci

# 3. Start PostgreSQL and ClickHouse containers
docker-compose up -d


# 4. Generate TypeORM migrations
npx squid-graphql-server


# 5. Configure PostgreSQL for logical replication and ClickHouse for real-time sync
chmod +x scripts/configure-replication.sh
./scripts/configure-replication.sh

# 6. Build and start the processor
sqd process

# 7. The command above will block the terminal
#    being busy with fetching the chain data, 
#    transforming and storing it in the target database.
#
#    To start the graphql server open the separate terminal
#    and run
sqd serve
```

A GraphiQL playground will be available at [localhost:4350/graphql](http://localhost:4350/graphql).

## Real-time Analytics with ClickHouse

This setup automatically replicates PostgreSQL data to ClickHouse for high-performance analytics:

### Setup Analytics Views
```bash
# Create materialized views for analytics (run after processor has created tables)
./scripts/setup-analytics.sh
```

### Monitor Replication
```bash
# Check replication status
docker-compose exec clickhouse clickhouse-client --multiquery < sql/monitoring.sql
```

### Example Analytics Queries
```sql
-- Daily USDC volume
SELECT day, sum(total_usdc) as daily_volume, sum(tx_count) as daily_txs
FROM analytics.mv_usdc_daily 
GROUP BY day 
ORDER BY day DESC 
LIMIT 7;

-- Top senders by volume
SELECT from_address, sum(total_sent) as volume 
FROM analytics.mv_top_senders 
GROUP BY from_address 
ORDER BY volume DESC 
LIMIT 10;

-- Transaction size distribution
SELECT size_bucket, sum(tx_count) as transactions, sum(total_volume) as volume
FROM analytics.mv_tx_size_distribution 
GROUP BY size_bucket 
ORDER BY volume DESC;
```

## Architecture

- **PostgreSQL**: Primary database with logical replication enabled
- **ClickHouse**: Analytics database with MaterializedPostgreSQL engine for real-time sync
- **Squid Processor**: Indexes Ethereum USDC transfers to PostgreSQL
- **GraphQL API**: Serves data from PostgreSQL
- **Analytics Views**: Pre-computed aggregations in ClickHouse for fast queries

## Manual Replication Setup

If you need to configure replication manually, here are the steps:

### 1. Start Services
```bash
docker-compose up -d
docker-compose ps  # Verify services are running
```

### 2. Configure PostgreSQL for Logical Replication
```bash
# Set WAL level to logical
docker-compose exec db psql -U postgres -d squid -c "ALTER SYSTEM SET wal_level = 'logical';"

# Set max replication slots
docker-compose exec db psql -U postgres -d squid -c "ALTER SYSTEM SET max_replication_slots = 2;"

# Reload configuration
docker-compose exec db psql -U postgres -d squid -c "SELECT pg_reload_conf();"

# Restart PostgreSQL to apply WAL level changes
docker-compose restart db

# Verify WAL level
docker-compose exec db psql -U postgres -d squid -c "SHOW wal_level;"

# Create publication for all tables
docker-compose exec db psql -U postgres -d squid -c "CREATE PUBLICATION usdc_pub FOR ALL TABLES;"
```

### 3. Configure ClickHouse MaterializedPostgreSQL
```bash
# Create blockchain database with MaterializedPostgreSQL engine
docker-compose exec clickhouse clickhouse-client --query "SET allow_experimental_database_materialized_postgresql = 1; CREATE DATABASE blockchain ENGINE = MaterializedPostgreSQL('db:5432', 'squid', 'postgres', 'postgres');"

# Create analytics database for materialized views
docker-compose exec clickhouse clickhouse-client --query "CREATE DATABASE analytics;"

# Verify databases were created
docker-compose exec clickhouse clickhouse-client --query "SHOW DATABASES;"
```

### 4. Setup Analytics Views (after processor creates tables)
```bash
# Create materialized views for analytics
docker-compose exec clickhouse clickhouse-client --multiquery < sql/analytics.sql
```

### 5. Monitor Replication
```bash
# Run monitoring queries
docker-compose exec clickhouse clickhouse-client --multiquery < sql/monitoring.sql
```

**Note**: ClickHouse automatically copies table schemas from PostgreSQL. When your Squid processor creates the `usdc_transfer` table, it will automatically appear in the `blockchain` database in ClickHouse with the same structure plus additional columns (`_sign`, `_version`) for replication tracking.

