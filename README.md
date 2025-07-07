# qx-db

Dual lineage tree database schema for Supabase.

## Architecture

See `architecture.md` for design invariants and `implementation.md` for development notes.

## Setup

```bash
supabase db reset
```

## Migration Order

Migrations must run in numbered sequence:
1. Core infrastructure (enums, utilities)
2. Node table
3. Tile, Link, Item tables
4. Access control
5. Data tables (text, file, user)