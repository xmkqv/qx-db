# qx-db

A polymorphic node-based database schema that powers the qx ecosystem, enabling flexible data modeling and spatial knowledge management.

## Overview

qx-db provides a universal data layer where any type of information can be stored as "nodes" with typed data attached. This design allows for maximum flexibility while maintaining referential integrity and type safety.

### Key Features

- **Polymorphic nodes**: All entities share a common base with type-specific data tables
- **Spatial organization**: Tiles and items enable 2D canvas-based UI representation
- **Relationship modeling**: Links for semantic connections, items for hierarchical structures
- **Type generation**: Automatic TypeScript and Python model generation
- **Real-time capable**: Built on Supabase for instant updates and subscriptions
- **Full-text search**: PostgreSQL text search on content

## Quick Start

```bash
# Start local development database
cd ../qx && qx db dev

# Run migrations
cd qx-db && supabase db push

# Generate TypeScript and Python types
cd ../qx && qx db gen-clients

# Reset
supabase db reset
```

## Database Design

### Core Tables

| Table         | Purpose                                            |
| ------------- | -------------------------------------------------- |
| `node`        | Base entity with id, type, timestamps, and creator |
| `node_access` | Permission grants for collaborative access         |
| `data_text`   | Text content (markdown, notes)                     |
| `data_file`   | File metadata (images, CSVs)                       |
| `data_user`   | User profiles with auth.users linkage              |
| `link`        | Bidirectional relationships between nodes          |
| `item`        | Hierarchical relationships with spatial context    |
| `tile`        | Visual representation on 2D canvas                 |

### Automatic Node Creation

When you insert into a data table, a node is automatically created:

```sql
-- This single insert:
INSERT INTO data_text (content) VALUES ('Hello world');

-- Automatically creates:
-- 1. A node with type='text'
-- 2. A data_text row linked to that node
```

### Authentication Entry Point

The `data_user` table connects Supabase authentication to your data graph:

```sql
-- Get user's node ID from auth
SELECT node_id FROM data_user WHERE user_id = auth.uid();

-- Create user profile on first login
INSERT INTO data_user (user_id, username, display_name)
VALUES (auth.uid(), 'username', 'Display Name')
ON CONFLICT (user_id) DO NOTHING;
```

### Collaborative Access

The system supports fine-grained permissions for collaborative workflows:

```sql
-- Grant read access to another user
INSERT INTO node_access (node_id, user_id, permission, granted_by)
VALUES (123, 'other-user-uuid', 'view', auth.uid());

-- Grant edit access to a collaborator
INSERT INTO node_access (node_id, user_id, permission, granted_by)
VALUES (123, 'collaborator-uuid', 'edit', auth.uid());

-- Check your permissions on a node
SELECT permission FROM accessible_nodes
WHERE node_id = 123 AND user_id = auth.uid();

-- Get all nodes you can access
SELECT n.*, dt.content, df.uri, du.username
FROM node n
JOIN accessible_nodes an ON n.id = an.node_id
LEFT JOIN data_text dt ON dt.node_id = n.id
LEFT JOIN data_file df ON df.node_id = n.id
LEFT JOIN data_user du ON du.node_id = n.id
WHERE an.user_id = auth.uid();
```

**Permission Levels:**

- `view`: Read-only access to node and its data
- `edit`: Can modify node and its relationships
- `admin`: Full control including granting access to others
- Creators automatically get `admin` permission on their nodes

### Querying Relationships

```sql
-- Find all connections for a node
SELECT * FROM get_nbrs(node_id);

-- Get linked nodes
SELECT * FROM get_dsts(node_id);  -- Outgoing links
SELECT * FROM get_srcs(node_id);  -- Incoming links

-- Get all accessible nodes with their data
SELECT n.*, dt.content, df.uri, du.username
FROM node n
JOIN accessible_nodes an ON n.id = an.node_id
LEFT JOIN data_text dt ON dt.node_id = n.id
LEFT JOIN data_file df ON df.node_id = n.id
LEFT JOIN data_user du ON du.node_id = n.id
WHERE an.user_id = auth.uid();

-- Get only node metadata without data (faster)
SELECT n.*
FROM node n
JOIN accessible_nodes an ON n.id = an.node_id
WHERE an.user_id = auth.uid();

-- Filter by node type
SELECT n.*
FROM node n
JOIN accessible_nodes an ON n.id = an.node_id
WHERE an.user_id = auth.uid()
  AND n.type = 'text';

-- Get nodes you created
SELECT * FROM node WHERE creator_id = auth.uid();
```

## Integration Points

- **qx-ui**: Frontend uses generated TypeScript types for type-safe database access
- **qx-ai**: Backend will integrate in Phase II for persistent conversation memory
- **qx**: Orchestrator manages migrations and type generation pipeline

## Project Structure

```
qx-db/
├── supabase/
│   ├── config.toml          # Supabase configuration
│   └── migrations/          # SQL migration files
├── CLAUDE.md               # Technical documentation
└── README.md              # This file
```

## Development Workflow

1. **Make schema changes**: Create a new migration

   ```bash
   supabase migration new add_new_feature
   ```

2. **Add new data types**: Follow the template in `data_type.template.md` for consistent patterns

3. **Apply migrations**: Push to local database

   ```bash
   supabase db push
   ```

4. **Generate types**: Update TypeScript/Python models

   ```bash
   cd ../qx && qx db gen-clients
   ```

5. **Test locally**: Verify with local Supabase instance
   ```bash
   cd ../qx && qx db test-dev
   ```

## Production Deployment

Production database is managed through Supabase Dashboard. The orchestrator provides helpers:

```bash
cd ../qx
qx db deploy      # Confirms production readiness
qx db test-prod   # Tests production connectivity
```

## Examples

### Working with Collaborative Access

```sql
-- Share a document with view-only access
BEGIN;
  -- Find the document to share
  SELECT id FROM node n
  JOIN data_text dt ON dt.node_id = n.id
  WHERE dt.content LIKE '%Project Plan%'
  AND n.creator_id = auth.uid()
  LIMIT 1;

  -- Grant view access (assuming node_id = 456)
  INSERT INTO node_access (node_id, user_id, permission)
  VALUES (456, 'viewer-uuid', 'view');
COMMIT;

-- Create a collaborative workspace
BEGIN;
  -- Create a folder node
  INSERT INTO data_text (content)
  VALUES ('# Team Workspace\nShared project resources');

  -- Grant team members edit access
  INSERT INTO node_access (node_id, user_id, permission)
  VALUES
    (currval('node_id_seq'), 'teammate1-uuid', 'edit'),
    (currval('node_id_seq'), 'teammate2-uuid', 'edit');
COMMIT;

-- Transfer ownership (grant admin to new owner)
INSERT INTO node_access (node_id, user_id, permission)
VALUES (789, 'new-owner-uuid', 'admin');
```

### Create a document with spatial representation

```sql
-- Create a text document
INSERT INTO data_text (content) VALUES ('# My Document\n\nContent here...');

-- Create a tile for visual representation
INSERT INTO tile (x, y, w, h, viewbox_x, viewbox_y, viewbox_zoom)
VALUES (100, 100, 400, 300, 0, 0, 1)
RETURNING id AS tile_id;

-- Link the document to its tile
INSERT INTO item (node_id, tile_id)
VALUES (currval('node_id_seq'), currval('tile_id_seq'));
```

### Link related content

```sql
-- Create a link between two nodes
INSERT INTO link (src_id, dst_id) VALUES (1, 2);

-- Find all linked content
SELECT n2.*, t.content
FROM link l
JOIN node n2 ON l.dst_id = n2.id
LEFT JOIN data_text t ON t.node_id = n2.id
WHERE l.src_id = 1;
```

## Technical Details

- **PostgreSQL 15+** for advanced features and performance
- **Supabase** for authentication, real-time, and API layer
- **Deferred constraints** ensure data integrity across transactions
- **Comprehensive indexes** for query performance
- **Trigger-based automation** for timestamps and data consistency

## License

Part of the qx ecosystem. See parent directory for license information.
