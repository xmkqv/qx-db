# QX Database

**Shared database schema and migrations for the QX ecosystem—single source of truth for data structures across all QX projects.**

## Notes

- **Purpose**: Centralized database definitions shared by qx-frontend and qx-backend
- **Database**: Supabase (PostgreSQL) with TypeScript type generation
- **Architecture**: Schema-first design with auto-generated types
- **Migrations**: Sequential SQL files in supabase/migrations
- **Type Safety**: Database types generated from schema for TypeScript projects
- **Authentication**: Supabase Auth integration with root-based ownership model

## Structure

```
qx-db/
├── supabase/
│   ├── config.toml          # Supabase configuration
│   └── migrations/          # SQL migration files
├── src/
│   ├── types/              # Generated TypeScript types
│   └── client/             # Database client implementations
└── docs/                   # Schema documentation
```

## Usage

### For TypeScript Projects

```typescript
import type { Database } from 'qx-db/types'
import { createClient } from 'qx-db/client'

const db = createClient(supabaseUrl, supabaseKey)
```

### For Python Projects

```python
from qx_db import get_schema, create_client

db = create_client(url, key)
```

## Schema Overview

### Core Tables

- **node**: Base entity (file or text)
- **root**: User authentication and ownership
- **link**: Relationships between nodes
- **tile**: UI layout components
- **item**: Content within tiles
- **file**: File data storage
- **text**: Text content storage

### Key Principles

- All tables have created_at/updated_at with automatic triggers
- UUID primary keys for distributed systems
- Root-based ownership model for multi-tenancy
- Optimistic locking via updated_at timestamps

## Development

### Generate Types

```bash
pnpm run generate-types
```

### Run Migrations

```bash
pnpm run migrate
```

### Reset Database

```bash
pnpm run reset
```