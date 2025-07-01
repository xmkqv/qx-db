#!/bin/bash
# migrate.sh - Create and apply database migrations

set -e  # Exit on error

# Check if migration name is provided
if [ -z "$1" ]; then
    echo "Usage: ./migrate.sh <migration_name>"
    echo "Example: ./migrate.sh add_user_preferences"
    exit 1
fi

echo "1. Creating migration: $1"
supabase migration new "$1"

echo "2. Applying migrations..."
supabase db push

# Create docs directory if it doesn't exist
mkdir -p docs

echo "3. Generating schema documentation..."
supabase db dump --schema-only > docs/schema.sql

echo "✓ Migration created and applied successfully"