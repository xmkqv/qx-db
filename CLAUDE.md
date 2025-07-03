# qx-db

Universal polymorphic database schema for the qx ecosystem, providing flexible data modeling through a node-based architecture.

## Notes

- **bytea**: The `bytea` type is used for binary data storage, such as files. This reflects the sql type BYTEA, and prevents name clashes in python with the `bytes` type.

## Architecture

- **Database**: PostgreSQL 15+ with Supabase
- **Access**: Direct SQL, Supabase REST API, and real-time subscriptions
- **Type Generation**: Automatic TypeScript and Python model generation via orchestrator
- **Pattern**: All data types reference a central `node` table via foreign key

## Core Concepts

### Polymorphic Node System

Every entity is a node with a type. Data tables (`data_text`, `data_file`, `data_user`, ...) store type-specific fields while referencing the base node:

```sql
-- Create a text node (auto-creates node via trigger)
INSERT INTO data_text (content) VALUES ('Hello, world!');

-- The trigger automatically:
-- 1. Creates a node with type='text'
-- 2. Links the text row to that node
-- 3. Maintains referential integrity
```

### Spatial Organization

The `tile` and `item` tables enable spatial UI representation:

- **Tiles**: Visual containers with position, size, and style
- **Items**: Associate nodes with tiles, supporting hierarchical nesting

### Relationships

Two types of connections:

- **Links**: Semantic relationships between any nodes (bidirectional)
- **Items**: Hierarchical parent-child relationships with spatial context

## Schema

### Tables

- `node`: Universal entity (id, type, created_at, updated_at, creator_id)
- `node_access`: Permission grants (node_id, user_id, permission, granted_by)
- `link`: Semantic relationships (src_id, dst_id)
- `item`: Hierarchical relationships (node_id, desc_id, next_id, tile_id)
- `tile`: Spatial representation (x, y, w, h, viewbox_x, viewbox_y, viewbox_zoom)
- `data_text`: Text content storage (node_id, content)
- `data_file`: File metadata (node_id, type, bytes, uri)
- `data_user`: User profiles with auth linkage (node_id, user_id, username, display_name, bio, avatar_url)

### Functions

- `trigger_set_updated_at()`: Auto-update timestamps
- `trigger_data_insert()`: Auto-create nodes when data inserted with creator tracking
- `check_node_has_data()`: Ensure every node has associated data
- `get_dsts(src_id)`: Get all destination nodes from links
- `get_srcs(dst_id)`: Get all source nodes to a node
- `get_nbrs(node_id)`: Get all neighbors (links + descendants)
- `get_items(item_id, variants)`: Get items with optional filtering

### Constraints

- Every node must have data (enforced by deferred trigger)
- Self-referential links/items prohibited
- Each tile can belong to only one item
- Unique constraints on node_id for data tables

## Type Generation

The orchestrator (`../qx`) generates type-safe clients:

```bash
# From qx directory
qx db gen-clients

# Generates:
# - ../qx-ui/src/gen/models.ts (TypeScript)
# - ../qx-ai/qx_ai/gen/models.py (Python SQLModel)
```

## Adding New Data Types

Follow the standardized pattern in `data_type.template.md` for consistent data\_\* table creation. Each data type requires:

1. Following the template for table structure and triggers
2. Manual updates to `check_node_has_data()` function
3. Adding to NODETYPE enum
4. Standard RLS policies

## Usage Examples

### Creating Nodes

```sql
-- Text node
INSERT INTO data_text (content) VALUES ('My note');

-- File node
INSERT INTO data_file (type, bytes, uri)
VALUES ('png'::FILETYPE, '\x89PNG...', '/uploads/image.png');

-- User node (user_id would be set from auth.uid() in practice)
INSERT INTO data_user (user_id, username, display_name)
VALUES ('123e4567-e89b-12d3-a456-426614174000', 'alice', 'Alice Smith');
```

### Creating Relationships

```sql
-- Link two nodes
INSERT INTO link (src_id, dst_id) VALUES (1, 2);

-- Create spatial hierarchy
INSERT INTO tile (x, y, w, h, viewbox_x, viewbox_y, viewbox_zoom)
VALUES (100, 200, 300, 400, 0, 0, 1);

INSERT INTO item (node_id, tile_id) VALUES (1, 1);
```

### Querying

```sql
-- Get all neighbors of a node
SELECT * FROM get_nbrs(1);

-- Find nodes with their data
SELECT n.*, t.content, f.uri, u.username
FROM node n
LEFT JOIN data_text t ON t.node_id = n.id
LEFT JOIN data_file f ON f.node_id = n.id
LEFT JOIN data_user u ON u.node_id = n.id;

-- Full-text search
SELECT * FROM data_text
WHERE to_tsvector('english', content) @@ plainto_tsquery('search term');
```

## Authentication Flow & User Data Graph

The `data_user` table serves as the entry point from Supabase authentication to the entire user data graph:

### 1. Login Entry Point

```sql
-- After authentication, find or create user node
WITH user_node AS (
  INSERT INTO data_user (user_id, username, display_name)
  VALUES (auth.uid(), 'new_user', 'New User')
  ON CONFLICT (user_id) DO UPDATE
  SET updated_at = NOW()
  RETURNING node_id
)
SELECT * FROM user_node;
```

### 2. Traversing from Auth to Full Graph

```sql
-- Step 1: Get user's node from auth ID
SELECT node_id FROM data_user WHERE user_id = auth.uid();

-- Step 2: Get all content owned by user (via links)
WITH user_node AS (
  SELECT node_id FROM data_user WHERE user_id = auth.uid()
)
SELECT n.*, dt.content, df.uri
FROM link l
JOIN node n ON l.dst_id = n.id
LEFT JOIN data_text dt ON dt.node_id = n.id
LEFT JOIN data_file df ON df.node_id = n.id
WHERE l.src_id = (SELECT node_id FROM user_node);

-- Step 3: Get user's spatial workspace (tiles/items)
WITH user_content AS (
  SELECT dst_id as node_id
  FROM link
  WHERE src_id = (SELECT node_id FROM data_user WHERE user_id = auth.uid())
)
SELECT i.*, t.*
FROM item i
JOIN tile t ON i.tile_id = t.id
WHERE i.node_id IN (SELECT node_id FROM user_content);
```

### 3. Complete User Data Decomposition

```sql
-- Get entire user graph in one query
WITH RECURSIVE user_graph AS (
  -- Start with user node
  SELECT node_id, 0 as depth
  FROM data_user
  WHERE user_id = auth.uid()

  UNION ALL

  -- Follow all links recursively
  SELECT
    CASE
      WHEN l.src_id = ug.node_id THEN l.dst_id
      ELSE l.src_id
    END as node_id,
    ug.depth + 1
  FROM user_graph ug
  JOIN link l ON l.src_id = ug.node_id OR l.dst_id = ug.node_id
  WHERE ug.depth < 5  -- Limit recursion depth
)
SELECT DISTINCT
  n.*,
  dt.content,
  df.uri,
  du.username
FROM user_graph ug
JOIN node n ON n.id = ug.node_id
LEFT JOIN data_text dt ON dt.node_id = n.id
LEFT JOIN data_file df ON df.node_id = n.id
LEFT JOIN data_user du ON du.node_id = n.id
ORDER BY n.created_at DESC;
```

### 4. Collaborative Access System

The authentication system supports collaborative workflows through explicit access grants:

```sql
-- Grant access to another user
INSERT INTO node_access (node_id, user_id, permission, granted_by)
VALUES (123, 'other-user-uuid', 'edit', auth.uid());

-- View all users with access to a node
SELECT u.username, na.permission, na.granted_at
FROM node_access na
JOIN data_user u ON u.user_id = na.user_id
WHERE na.node_id = 123;

-- Query for all accessible content
SELECT n.*, dt.content, df.uri, du.username
FROM node n
JOIN accessible_nodes an ON n.id = an.node_id
LEFT JOIN data_text dt ON dt.node_id = n.id
LEFT JOIN data_file df ON df.node_id = n.id
LEFT JOIN data_user du ON du.node_id = n.id
WHERE an.user_id = auth.uid();
```

### 5. Access Control Model

- **Creator Access**: Node creators automatically get admin permission
- **Explicit Grants**: Use `node_access` table for sharing
- **Permission Levels**:
  - `view`: Read-only access
  - `edit`: Can modify content
  - `admin`: Full control including granting access
- **Row Level Security**: All queries automatically filtered by access

The `accessible_nodes` view combines creator and granted access for efficient permission checks across all queries.

## Integration

- **Frontend** (`../qx-ui`): Uses generated TypeScript types with Supabase client
- **Backend** (`../qx-ai`): Will use generated Python models (planned for Phase II)
- **Orchestrator** (`../qx`): Manages migrations and type generation

## Development

```bash
# Start local Supabase
cd ../qx && qx db dev

# Create new migration
supabase migration new my_migration

# Apply migrations
supabase db push

# Generate types
cd ../qx && qx db gen-clients
```

## Future Considerations

- Row Level Security (RLS) policies for multi-tenant access
- Partitioning strategy when node table exceeds 10M records
- Vector embeddings for semantic search
- Audit trails for compliance requirements
