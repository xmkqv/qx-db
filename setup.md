# qx Setup

## Environment Variables

```bash
# Add to your .env.local file:

# For local Supabase development
VITE_DB_URL=postgresql://postgres:postgres@localhost:54322/postgres
VITE_SUPABASE_API_KEY=your-anon-key-from-supabase-start

# The anon key is displayed when you run 'supabase start'
# Or find it in: http://localhost:54323/settings/api
```

## Install and Run

```bash
# Install Supabase CLI
brew install supabase/tap/supabase

# Initialize project (one time)
cd /path/to/qx
supabase init

# Start it
supabase start

# That's it. Access at:
# Database: postgresql://postgres:postgres@localhost:54322/postgres
# Studio UI: http://localhost:54323
```

## Keep It Running

```bash
# Add to your ~/.zshrc or ~/.bashrc
alias qx-start='cd ~/projects/qx && supabase start'
alias qx-stop='cd ~/projects/qx && supabase stop'

# Now just run:
qx-start  # Starts in background
qx-stop   # When you need to stop
```

## Package.json Scripts

```json
{
  "scripts": {
    "db:migrate": "supabase migration new",
    "db:generate": "tsx scripts/generate-triggers.ts",
    "db:push": "supabase db push && npm run db:generate && supabase db push",
    "types": "supabase gen types typescript --local > src/types/supabase.ts"
  }
}
```