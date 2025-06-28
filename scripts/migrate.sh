#!/bin/bash
# migrate.sh

# 1. Write migration
supabase migration new $1

# 2. Apply
supabase db push

# 3. Generate docs
supabase db dump --schema-only > docs/schema.sql