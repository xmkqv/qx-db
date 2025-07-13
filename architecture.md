# Dual Lineage Tree Architecture

## Terms Registry

- **Ascendant**: Item referenced by ascn_id
- **Branch**: All items reachable from a stem's desc_id following next_id chains
- **Branch Head**: Item that serves as desc_id target for other items
- **Branch Queries**: Efficient descendant lookup via ascn_id index
- **Descendant**: Item referenced by desc_id
- **Flux**: Discontinuity where descendant.ascn_id ≠ stem.id
- **Flux Detection**: Composition identified by ascn_id discontinuity
- **Flux Item**: An item in flux condition with its stem
- **Flux Point**: Where ascn_id discontinuity occurs (composition boundary)
- **Foreign Key (FK)**: Database constraint linking tables via shared values
- **Graph**: A collection of nodes connected by edges
- **Head**: An item referenced by any other item's desc_id (branch origin)
- **Invariant**: A condition that must always be true
- **Item**: A structure element in a tree, represented by the `item` table
- **Native Branch**: Subset of branch where items have ascn_id = stem.id
- **Native Growth**: Items created with ascn_id = stem.id
- **Native Item**: Item where ascn_id = stem.id
- **Next Peer**: Item referenced by next_id
- **ON DELETE CASCADE**: Delete rows in referencing table when referenced row deleted
- **ON DELETE SET NULL**: Set FK to NULL when referenced row deleted
- **ON DELETE TRIGGER**: Custom deletion logic (see Deletion Cases)
- **Referenced Table**: Table containing the primary key being referenced
- **Referencing Table**: Table containing the foreign key
- **Root**: An item with ascn_id = NULL
- **Stem**: Item whose desc_id points to a descendant

## Invariants

### I1: Universal Node Identity
Every entity is a node, or refers to a node (data_*), connects nodes (link, item), or visualizes nodes (tile).

### I2: Data-Node Bijection
Every node has exactly one data_* entry. Every data_* entry has exactly one node.

### I3: Referential Integrity  
All pointers must reference existing entities or be null.

### I4: Tree Traversability
Every tree must be traversable from well-defined root items (ascn_id = NULL).

### I5: Tree Composition
Every tree can be composed from other trees via item desc_id references.

### I6: Lifecycle Authority
Nodes own the lifecycle data_* and connections.

### I7: Permission Authority
Nodes are the authoritative source for all access control. RLS constrains authenticated user access (low pass filter) and the node_access table with Unix-style permission bits defines fine-grained access control.

### I8: Cycles Permitted
Cycles in tree composition are explicitly allowed (except self-reference). Traversal must handle cycles gracefully.

### I9: Ids are Immutable
All IDs are immutable (ON UPDATE RESTRICT) except external auth.users.id (ON UPDATE CASCADE).

## Maxims

### P1: Ascendant Assignment (from I5)
- Native descendants: `new_item.ascn_id = stem.id`
- Flux descendants: `new_item.ascn_id` preserves ascendant lineage
- Branch queries: `WHERE ascn_id = stem.id` OR `id = stem.desc_id`

### P2: Flux as Feature (from I5)
- Flux occurs where descendant.ascn_id ≠ stem.id, enabling tree composition
- Items track dual lineage: ascn_id (ascendant) and desc_id (stem)
- No special entities needed - discontinuity IS the marker

### P3: Flux Constraints & Permissions (from I5, I6, I7)
- Flux items are ALWAYS heads (no incoming next_id)
- Stem owns lifecycle of flux descendants
- Flux descendants require permission checks on both lineages via node_access
- Least permissive wins at flux boundaries

### P4: Root Simplicity (from I4)
Trees start at roots (ascn_id = NULL) with no explicit containers.

### P5: Cycle Handling (from I8)
Path tracking prevents infinite loops, enabling recursive structures.

### P6: Simplified Lifecycle (from I6)
Direct relationships with clean deletion cascades via ascn_id.

## Schema

```sql
-- Core Types
NodeType: ENUM('text', 'file', 'user')
FileType: ENUM('png')

-- Node (universal entity)
CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  type NodeType NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Item (tree structure)
CREATE TABLE item (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  ascn_id INTEGER REFERENCES item(id) ON DELETE CASCADE,
  desc_id INTEGER REFERENCES item(id) ON DELETE TRIGGER,
  next_id INTEGER REFERENCES item(id) ON DELETE TRIGGER,
  tile_id INTEGER REFERENCES tile(id) ON DELETE SET NULL,
  CHECK (id != ascn_id AND id != desc_id AND id != next_id)
);

-- Link (node connections)
CREATE TABLE link (
  id SERIAL PRIMARY KEY,
  src_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  dst_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  CHECK (src_id != dst_id)
);

-- Tile (visualization)
CREATE TABLE tile (
  id SERIAL PRIMARY KEY,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  w INTEGER NOT NULL,
  h INTEGER NOT NULL,
  viewbox_x INTEGER NOT NULL DEFAULT 0,
  viewbox_y INTEGER NOT NULL DEFAULT 0,
  viewbox_zoom REAL NOT NULL DEFAULT 1.0
);

-- Data Tables
CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  content TEXT NOT NULL
);

CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  type FileType NOT NULL,
  bytea BYTEA NOT NULL
);

CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL UNIQUE,
  username TEXT NOT NULL UNIQUE,
  bio TEXT,
  head_item_id INTEGER REFERENCES item(id) ON DELETE SET NULL
);

-- Access Control (Unix-style permission bits)
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE ON UPDATE CASCADE,
  permission_bits INTEGER NOT NULL DEFAULT 4,  -- 4=view, 2=edit, 1=admin
  UNIQUE(node_id, user_id),
  CHECK (permission_bits >= 0 AND permission_bits <= 7)
);

-- Indexes
CREATE INDEX index_item__ascn_id ON item(ascn_id);
CREATE INDEX index_item__desc_id ON item(desc_id);
CREATE INDEX index_item__next_id ON item(next_id);
CREATE INDEX index_item__node_id ON item(node_id);
CREATE INDEX index_item__root ON item(id) WHERE ascn_id IS NULL;
CREATE INDEX index_item__id__ascn_id ON item(id, ascn_id);
CREATE INDEX index_item__desc_id_not_null ON item(id) WHERE desc_id IS NOT NULL;
```

## Deletion Cases

When deleting an item: Flux items (where ascn_id ≠ stem.id) cannot be deleted independently per P3.

| Case | Root? | Native Desc? | Head? | Peers? | Solution |
|------|-------|-------------|-------|--------|----------|
| R1 | Yes | Yes | - | - | Cascade Delete |
| R2 | Yes | No | Yes | - | Head Repoint |
| R3 | Yes | No | No | - | Simple Delete |
| N1 | No | Yes | No | No | Native Cascade |
| N2 | No | Yes | Yes | No | Dual Update |
| N3 | No | Yes | No | Yes | Native Cascade + Splice |
| H1 | No | No | Yes | No | Head Repoint (blocked if flux) |
| H2 | No | No | Yes | Yes | Head Repoint + Splice |
| P1 | No | No | No | Yes | Peer Splice |
| T1 | No | No | No | No | Terminal Delete |

## Referential Integrity

```
item.ascn_id → item.id: CASCADE
item.desc_id → item.id: TRIGGER (see Deletion Cases)
item.next_id → item.id: TRIGGER (see Deletion Cases)
item.node_id → node.id: CASCADE
item.tile_id → tile.id: SET NULL

data_*.node_id → node.id: CASCADE (Direct DELETE prohibited)
data_user.head_item_id → item.id: SET NULL

node_access.node_id → node.id: CASCADE
node_access.user_id → auth.users.id: CASCADE, CASCADE on update

link.src_id → node.id: CASCADE
link.dst_id → node.id: CASCADE
```

## Access Control

### Permission System
Unix-style permission bits in node_access table:
- 4 = VIEW (read)
- 2 = EDIT (write)  
- 1 = ADMIN (execute/delete)
- 7 = Full access (4+2+1)
- 6 = View + Edit (4+2)
- 4 = View only

### Ownership
- Creator gets automatic admin (7) via trigger on node insert
- Additional permissions granted via node_access table
- Most permissive grant wins

### Flux Permissions
Items in flux require permission via BOTH lineages. Least permissive wins.

```
CHECK_ACCESS(node_id, user_id, required_bits):
  1. Check node_access for (permission_bits & required_bits) = required_bits
  2. If node is part of flux item:
     a. Check permission via stem lineage
     b. Check permission via ascendant lineage  
     c. Return TRUE only if BOTH grant required permission
  3. Return result from step 1
```

## Tree Mechanics & Traversal

### Key Relationships
- `ascn_id`: Ascendant lineage
- `desc_id`: Stem lineage (branch head)
- `next_id`: Peer chain
- Flux: `descendant.ascn_id ≠ stem.id`

### Essential Queries
```sql
-- Get branch
WHERE item.ascn_id = stem.id OR item.id = stem.desc_id

-- Detect flux
FROM stem s JOIN descendant d ON s.desc_id = d.id
WHERE s.id ≠ d.ascn_id

-- Is head?
EXISTS(SELECT 1 FROM item WHERE desc_id = item.id)

-- Ascendant chain
start_id → ascn_id → ascn_id → ... → NULL

-- Stem traversal
desc_id → descendant, next_id → peer (track cycles, limit depth)
```

## Performance

### Boundaries
- Max depth: 20 levels
- Timeout: 5s
- Work memory: 256MB for recursive queries

### Expected Latency
- Ascendant lookup: O(1), <1ms
- Tree composition: O(1) UPDATE, <5ms
- Origin traversal: O(depth), ~2ms/level
- Flux detection: O(1) comparison, <1ms
- Permission check: O(depth) both paths, <50ms typical

### Key Strengths
- Fast ascendant lookup via ascn_id index
- Single UPDATE operations for composition/movement
- Direct pointer traversal without indirection

## Comparison

| Aspect | Advantage | Disadvantage |
|--------|-----------|--------------|
| Structure | Normalized, direct relationships | No explicit tree containers |
| Operations | Fast index-based lookups | Tree-wide queries need traversal |
| Composition | Natural via flux | Cycle validation overhead |
| Lineage | Dual model preserves origin | Two traversal patterns |

## Patterns & Resolutions

### Tree Composition
**Need**: Include subtree from different tree  
**Solution**: `fn_item_compose(local_id, external_id)` maintains dual lineage

### Tree Extraction
**Need**: Remove composed subtree  
**Solution**: `UPDATE item SET desc_id = NULL WHERE id = mount_point`

### Native Growth
**Need**: Add item to tree  
**Solution**: Set ascn_id = stem.id for native growth
```sql
INSERT INTO item (node_id, ascn_id) VALUES (new_node_id, stem_item_id);
UPDATE item SET desc_id = new_item_id WHERE id = stem_item_id;
```

### Circular Origins
**Issue**: A→B, B→A  
**Solution**: Trigger prevents cycles

### Composition Cycles
**Issue**: A→B→C→A  
**Solution**: Path tracking, depth limits
**Consequences**: Same subtree can appear multiple times; enables recursive structures

### Cross-Tree References
**Issue**: desc_id to different tree  
**Solution**: Feature - this IS composition

### Permission Conflicts
**Issue**: Which lineage wins?  
**Solution**: Least permissive

### User Workspaces
**Issue**: Entry points needed  
**Solution**: data_user.head_item_id

### Deferred Visualization
**Issue**: Items without tiles  
**Solution**: tile_id = NULL until needed

## Implementation Notes

1. **Ascendant Assignment**: Determine ascn_id at creation (native: stem.id, flux: preserved)
2. **Flux Constraints**: Validate flux items are heads
3. **User Entry**: Every user needs a root item (head_item_id) - auto-create with user
4. **Cycle Detection**: Trigger validation on ascn_id
5. **Permission Boundaries**: Start simple, enhance as needed

## Exclusions

- Read replicas for complex queries
- Caching layer for flux detection
- Mock data generation
- Composition metadata
- Tree versioning
- Spatial indexes
- Performance monitoring

## Alternative Architectures

- **Mount-Based**: Uses memo indirection
- **Fork-Based**: Every item carries memo_id
- **Memo-ID Based**: Similar to fork with different semantics

Selected ascendant-based for schema simplicity and natural composition.

## Trade-Offs

1. **Tree Identity vs Simplicity**: No containers but simpler schema
2. **Dual Traversal**: Two patterns but rich semantics
3. **Integer IDs vs UUIDs**: Space efficient but needs sequence management
4. **Users as data_user**: Consistent pattern, join overhead acceptable