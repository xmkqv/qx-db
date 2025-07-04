# qx-db Architecture

## Invariants

These fundamental requirements define the system and cannot be violated:

### I1: Universal Node Identity
Every entity in the system is a node with unique identity, type, and timestamps.

### I2: Data-Node Coupling  
Data cannot exist without a node. Every node must have exactly one associated data entry.

### I3: Referential Integrity
Invalid references cannot exist. All pointers must reference existing entities or be null.

### I4: Tree Traversability
Every treelet must be traversable from a well-defined entrypoint.

### I5: Polymorphic Storage
Nodes provide uniform interface to heterogeneous data types.

### I6: Graph Composition
Same node can appear in multiple tree positions through indirection.

### I7: Lifecycle Authority
Nodes own the lifecycle of their data and connections.

## Design Principles

Derived from invariants, these principles guide implementation:

### P1: Reverse Ownership Pattern
*From I2, I7: Data tables reference nodes via foreign key*
- Data tables have `node_id` FK to `node.id` with CASCADE DELETE
- Prohibit direct INSERT/DELETE on data tables
- All data manipulation flows through node operations

### P2: Polymorphic Node Architecture  
*From I1, I5: Flexible entity model*
- Node table contains shared attributes (id, type, timestamps)
- Type-specific data stored in `data_*` tables
- Node type discriminates which data table contains content

### P3: Dual Connection Types
*From I6: Support both hierarchical and semantic relationships*
- `item` for tree structure (desc_id, next_id pointers)
- `link` for semantic relationships (src_id, dst_id)

### P4: Memo Indirection
*From I4, I6: Enable tree composition*
- `data_memo` acts as container for treelets
- Memo proxy pattern: item → node[memo] → data_memo → item
- Allows mounting treelets within other treelets

### P5: Constraint-Based Integrity
*From I3: Database enforces structural validity*
- Foreign keys prevent dangling references
- Triggers maintain consistency during mutations
- Check constraints validate type coherence

## Schema

Each table and constraint directly implements specific invariants:

### Core Tables

```sql
-- node: Universal entity container
-- Enforces: I1 (universal identity), I5 (polymorphic storage)
CREATE TABLE node (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type NodeType NOT NULL,  -- Discriminator for data_* lookup
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    creator_id UUID  -- References user who created
);

-- node_access: Permission grants
-- Enforces: I7 (lifecycle authority)
CREATE TABLE node_access (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    permission PermissionType NOT NULL,
    granted_by UUID NOT NULL,
    granted_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(node_id, user_id)
);
CREATE INDEX idx_node_access_user ON node_access(user_id, node_id);

-- link: Semantic relationships  
-- Enforces: P3 (dual connections), I3 (referential integrity)
CREATE TABLE link (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    src_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    dst_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    CHECK (src_id != dst_id)  -- Prevent self-links
);
CREATE INDEX idx_link_src_dst ON link(src_id, dst_id);
CREATE INDEX idx_link_dst ON link(dst_id);

-- item: Tree positions
-- Enforces: I4 (traversability), I6 (graph composition)
CREATE TABLE item (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    desc_id UUID REFERENCES item(id) ON DELETE SET NULL,  -- First descendant
    next_id UUID REFERENCES item(id) ON DELETE SET NULL,  -- Next peer
    tile_id UUID REFERENCES tile(id) ON DELETE SET NULL,
    CHECK (id != desc_id AND id != next_id)  -- Prevent self-reference
);
CREATE INDEX idx_item_desc ON item(desc_id);
CREATE INDEX idx_item_next ON item(next_id);

-- tile: Spatial representation
-- Supports: Item rendering
CREATE TABLE tile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    w INTEGER NOT NULL,
    h INTEGER NOT NULL,
    viewbox_x INTEGER DEFAULT 0,
    viewbox_y INTEGER DEFAULT 0,
    viewbox_zoom REAL DEFAULT 1.0
);
```

### Data Tables

Each data table follows the reverse ownership pattern (P1):

```sql
-- data_text: Text content storage
-- Enforces: I2 (data-node coupling), P1 (reverse ownership)
CREATE TABLE data_text (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    tsvector tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);
CREATE INDEX idx_data_text_node ON data_text(node_id);
CREATE INDEX idx_data_text_fts ON data_text USING GIN(tsvector);

-- data_file: File metadata
-- Enforces: I2, P1
CREATE TABLE data_file (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    type FileType NOT NULL,
    bytes INTEGER NOT NULL,
    uri TEXT NOT NULL
);
CREATE INDEX idx_data_file_node ON data_file(node_id);

-- data_user: User profiles  
-- Enforces: I2, P1, I4 (via memo_id)
CREATE TABLE data_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    user_id UUID NOT NULL UNIQUE,  -- Auth system ID
    username TEXT NOT NULL UNIQUE,
    display_name TEXT,
    bio TEXT,
    avatar_url TEXT,
    memo_id UUID NOT NULL  -- User's root workspace
);
CREATE INDEX idx_data_user_node ON data_user(node_id);

-- data_memo: Treelet containers
-- Enforces: I4 (traversability), I6 (graph composition), P4 (memo indirection)
CREATE TABLE data_memo (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    desc_id UUID REFERENCES item(id) ON DELETE SET NULL  -- Treelet entrypoint
);
CREATE INDEX idx_data_memo_node ON data_memo(node_id);
```

### Type Enums

```sql
-- Node types determine data table
CREATE TYPE NodeType AS ENUM ('text', 'file', 'user', 'memo');

-- File type constraints
CREATE TYPE FileType AS ENUM ('png', 'jpg', 'pdf', 'mp4', 'json');

-- Permission levels for access control
CREATE TYPE PermissionType AS ENUM ('view', 'edit', 'admin');
```

### Constraint Enforcement

Key triggers and functions that maintain invariants:

```sql
-- Automatic timestamp updates
-- Supports: Audit trail
CREATE FUNCTION trigger_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Auto-create nodes for data inserts  
-- Enforces: I2 (data-node coupling), P1 (reverse ownership)
CREATE FUNCTION trigger_data_insert() RETURNS TRIGGER AS $$
DECLARE
    new_node_id UUID;
    table_type NodeType;
BEGIN
    -- Determine node type from table name
    table_type := TG_TABLE_NAME;
    
    -- Create node first
    INSERT INTO node (type, creator_id) 
    VALUES (table_type, auth.uid())
    RETURNING id INTO new_node_id;
    
    -- Link data to node
    NEW.node_id := new_node_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Verify every node has data
-- Enforces: I2 (data-node coupling)
CREATE FUNCTION check_node_has_data() RETURNS TRIGGER AS $$
BEGIN
    -- Check each data table for this node
    IF NOT EXISTS (
        SELECT 1 FROM data_text WHERE node_id = NEW.id
        UNION
        SELECT 1 FROM data_file WHERE node_id = NEW.id
        UNION
        SELECT 1 FROM data_user WHERE node_id = NEW.id
        UNION
        SELECT 1 FROM data_memo WHERE node_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'Node % has no associated data', NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER node_check_data
    AFTER INSERT ON node
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_node_has_data();
```

## Tree Traversal Patterns

### Terminology

- **Branch**: Chain of items connected by `next_id` pointers
- **Stem**: Item whose `desc_id` points to a branch
- **Peers**: Items within same branch
- **Branching**: Following a `desc_id` to new level
- **Memo Proxy**: Item with node.type='memo', mounts treelet

### Core Traversal

```sql
-- Recursive tree walk with cycle detection
-- Implements: I4 (traversability)
WITH RECURSIVE tree_walk AS (
    -- Base: start from item
    SELECT 
        i.id,
        i.node_id,
        i.desc_id,
        i.next_id,
        0 as depth,
        ARRAY[i.id] as path,
        false as is_cycle
    FROM item i
    WHERE i.id = $1
    
    UNION ALL
    
    -- Recurse: follow pointers
    SELECT 
        child.id,
        child.node_id,
        child.desc_id,
        child.next_id,
        parent.depth + 1,
        parent.path || child.id,
        child.id = ANY(parent.path) as is_cycle
    FROM tree_walk parent
    INNER JOIN item child ON (
        child.id = parent.desc_id OR  -- Branch down
        child.id = parent.next_id      -- Continue branch
    )
    WHERE NOT parent.is_cycle
      AND parent.depth < 20  -- Depth limit
)
SELECT * FROM tree_walk;
```

### Memo Resolution

```sql
-- Handle memo indirection transparently
-- Implements: P4 (memo indirection)
CREATE FUNCTION resolve_memo_proxy(item_id UUID) 
RETURNS UUID AS $$
    SELECT COALESCE(
        -- If memo, return its treelet entry
        (SELECT dm.desc_id 
         FROM item i 
         JOIN node n ON i.node_id = n.id 
         JOIN data_memo dm ON dm.node_id = n.id 
         WHERE i.id = item_id AND n.type = 'memo'),
        -- Otherwise return item itself
        item_id
    );
$$ LANGUAGE SQL;
```

## Access Control

### Permission Model

Based on node ownership and explicit grants:

1. **Creator Access**: Automatic admin permission
2. **Explicit Grants**: Via node_access table  
3. **Permission Levels**:
   - `view`: Read-only access
   - `edit`: Can modify content
   - `admin`: Full control including granting access

### RLS Implementation

```sql
-- Accessible nodes view combines creator and granted access
CREATE VIEW accessible_nodes AS
SELECT DISTINCT n.id as node_id, u.user_id
FROM node n
LEFT JOIN node_access na ON n.id = na.node_id
CROSS JOIN LATERAL (
    SELECT n.creator_id as user_id
    UNION
    SELECT na.user_id
) u
WHERE u.user_id IS NOT NULL;

-- Enable RLS on all tables
ALTER TABLE node ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_text ENABLE ROW LEVEL SECURITY;
-- etc...

-- Node access policy
CREATE POLICY node_access_policy ON node
    FOR ALL
    USING (EXISTS (
        SELECT 1 FROM accessible_nodes an 
        WHERE an.node_id = id 
        AND an.user_id = auth.uid()
    ));
```

## Query Patterns

### User Entry

```sql
-- Get user's workspace
SELECT dm.desc_id as root_item_id
FROM data_user du
JOIN data_memo dm ON dm.node_id = du.memo_id
WHERE du.user_id = auth.uid();
```

### Tree Operations

```sql
-- Get branch (all peers)
WITH RECURSIVE branch AS (
    SELECT id, 0 as position
    FROM item WHERE id = $1
    
    UNION ALL
    
    SELECT i.id, b.position + 1
    FROM branch b
    JOIN item i ON i.id = b.next_id
    WHERE b.position < 1000
)
SELECT * FROM branch ORDER BY position;

-- Get all descendants
WITH RECURSIVE descendants AS (
    SELECT i.*, 0 as depth
    FROM item i WHERE id = $1
    
    UNION ALL
    
    SELECT i.*, d.depth + 1
    FROM descendants d
    JOIN item i ON i.id = d.desc_id
    WHERE d.depth < 20
)
SELECT * FROM descendants;
```

## Performance Considerations

### Indexes
- Foreign key columns for joins
- Traversal pointers (desc_id, next_id)
- Full-text search on content

### Limits
- Query depth: 20 levels
- Branch size: 1000 items
- Statement timeout: 5s

### Future Optimizations
- Materialized path cache
- Read replicas for queries
- Partitioning by workspace

## Failure Modes

### Prevented by Design
- Orphaned data (CASCADE DELETE)
- Dangling references (FK constraints)
- Missing workspaces (user trigger)
- Type mismatches (enum constraints)

### Handled Failures
- Concurrent updates (last-write-wins)
- Query limits (clean termination)
- Constraint violations (standard errors)

## Migration Strategy

All schema changes via versioned migrations:
- Prefer additive changes (new columns/tables)
- Test on production data copy
- Use IF NOT EXISTS for idempotency
- Document rollback procedures