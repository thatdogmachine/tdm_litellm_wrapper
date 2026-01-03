#!/usr/bin/env bash
# One-time script to initialize the Letta database on the host PostgreSQL

echo "Checking for 'letta' user..."
if psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='letta'" | grep -q 1; then
    echo "User 'letta' already exists."
else
    echo "Creating user 'letta'..."
    psql -U postgres -c "CREATE USER letta WITH SUPERUSER;"
fi

echo "Checking for 'letta' database..."
if psql -U postgres -lqt | cut -d \| -f 1 | grep -qw letta; then
    echo "Database 'letta' already exists."
else
    echo "Creating database 'letta'..."
    psql -U postgres -c "CREATE DATABASE letta OWNER letta;"
fi

echo "Enabling pgvector extension in 'letta' database..."
psql -U postgres -d letta -c "CREATE EXTENSION IF NOT EXISTS vector;"
