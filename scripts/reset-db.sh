#!/bin/bash

set -e  # Exit on any error

echo "🔄 Resetting databases and regenerating client code..."

echo "📍 Step 1: Reset local database"
npm run db:reset

echo "📍 Step 2: Push migrations to remote (resets remote)"
npm run db:migrate

echo "📍 Step 3: Regenerate TypeScript models"
npm run db:gen-models

echo "✅ Database reset and client code regeneration complete!"