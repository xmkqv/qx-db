# Dual Lineage Tree Architecture

## Invariants

**Terms**:
- **Invariant**: A condition that must always be true, regardless of system state, the irreducible requirements
- **Graph**: A collection of nodes connected by edges
- **Item**: A structure element in a tree, represented by the `item` table
- **Ascendant**: Item referenced by ascn_id
- **Descendant**: Item referenced by desc_id
- **Next Peer**: Item referenced by next_id
- **Root**: An item with ascn_id = NULL
- **Head**: An item referenced by any other item's desc_id (branch origin)
- **Stem**: Item whose desc_id points to a descendant
- **Branch**: All items reachable from a stem's desc_id following next_id chains
- **Native Branch**: Subset of branch where items have ascn_id = stem.id
- **Native Descendant**: Descendant where descendant.ascn_id = stem.id
- **Flux Condition**: When descendant.ascn_id ≠ stem.id
- **Flux**: Discontinuity where descendant.ascn_id ≠ stem.id
- **Flux Item**: An item in a flux condition with its stem
- **Flux Descendant**: Descendant at a flux point, composed from different tree

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
Nodes are the authoritative source for all access control.

### I8: Cycles Permitted
Cycles in tree composition are explicitly allowed (except self-reference). Traversal must handle cycles gracefully.

## Maxims

**Terms**:
- **Flux Detection**: Composition identified by ascn_id discontinuity
- **Native Growth**: Items created with ascn_id = stem.id
- **Branch Queries**: Efficient descendant lookup via ascn_id index

### P1: Ascendant Assignment (from I5)
- Native descendants: `new_item.ascn_id = stem.id`
- Flux descendants: `new_item.ascn_id` preserves ascendant lineage
- Branch queries: `WHERE ascn_id = stem.id` OR `id = stem.desc_id`

### P2: Flux as Feature (from I5)
- Flux occurs where descendant.ascn_id ≠ stem.id, enabling tree composition.
- Items track dual lineage: ascn_id (ascendant lineage) and desc_id (stem lineage). 
- Flux points mark tree composition boundaries
- No special entities needed - discontinuity IS the marker
- Cross-tree desc_id references create flux naturally

### P3: Flux Constraints (from I5, I6)
- Flux items are ALWAYS heads (no incoming next_id)
- Stem owns lifecycle of flux descendants
- Client handles visual discontinuity appropriately

### P4: Root Simplicity (from I4)
- Trees start at roots (ascn_id = NULL)
- No explicit containers or identity needed
- Tree membership is implicit via ancestry

### P5: Cycle Handling (from I8)
- Cycles create infinite traversal possibilities
- Path tracking prevents infinite loops
- Cycle points can be detected and reported
- Enables recursive structures (e.g., templates referencing themselves)

### P6: Simplified Lifecycle (from I6)
- Direct ascendant-descendant relationships
- Simple entity lifecycle management
- Clean deletion cascades via ascn_id

### P7: Flux-Aware Permissions (from I7)
- Native descendants inherit stem permissions naturally
- Flux descendants require checks on both lineages
- Least permissive wins at flux boundaries (must have permission via BOTH paths)
- Security preserved across tree composition

## Critical Design Decisions

**Terms**:
- **Branch Head**: Item that serves as desc_id target for other items
- **Flux Point**: Where ascn_id discontinuity occurs (composition boundary)
- **Native Item**: Item where ascn_id = stem.id
- **Flux Item**: Item where ascn_id ≠ stem.id (in flux condition with its stem)

### Item Deletion Trigger Logic

When deleting an item in the dual lineage model:

**Note**: Flux items (where ascn_id ≠ stem.id) cannot be deleted independently per P3.

#### Deletion Cases Matrix

| Case | Root? | Has Native Desc? | Acts as Head? | Has Peers? | Solution |
|------|-------|-----------------|---------------|------------|----------|
| R1 | Yes | Yes | - | - | **Cascade Delete**: Native descendants deleted via CASCADE |
| R2 | Yes | No | Yes | - | **Head Repoint**: Update desc_id references to NULL |
| R3 | Yes | No | No | - | **Simple Delete**: No complications |
| N1 | No | Yes | No | No | **Native Cascade**: Descendants deleted via ascn_id CASCADE |
| N2 | No | Yes | Yes | No | **Dual Update**: Cascade natives, repoint heads |
| N3 | No | Yes | No | Yes | **Native Cascade + Splice**: Delete descendants, splice peers |
| H1 | No | No | Yes | No | **Head Repoint**: Stem's desc_id updated (blocked if flux) |
| H2 | No | No | Yes | Yes | **Head Repoint + Splice**: Complex repointing |
| P1 | No | No | No | Yes | **Peer Splice**: Update predecessor's next_id |
| T1 | No | No | No | No | **Terminal Delete**: No repointing needed |

## Schema Definitions

**Terms**:
- **Foreign Key (FK)**: Database constraint linking tables via shared values
- **Referencing Table**: The table containing the foreign key (FK holder)
- **Referenced Table**: The table containing the primary key being referenced
- **ON DELETE CASCADE**: When row in referenced table deleted, delete rows in referencing table
- **ON DELETE SET NULL**: When row in referenced table deleted, set FK to NULL in referencing table
- **ON DELETE TRIGGER**: Custom logic executes on deletion (see Deletion Matrix)

### Tables

```sql
-- Node table with auto-incrementing IDs
CREATE TABLE node (
  id SERIAL PRIMARY KEY,  -- Auto-incrementing integer
  type NodeType NOT NULL,  -- Immutable after creation
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL  -- Creator has automatic admin permission
);

-- Enhanced item table with ascn_id
CREATE TABLE item (
  id SERIAL PRIMARY KEY,  -- Auto-incrementing integer
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  ascn_id INTEGER REFERENCES item(id) ON DELETE CASCADE,  -- Ascendant
  desc_id INTEGER REFERENCES item(id) ON DELETE TRIGGER,  -- Head of branch
  next_id INTEGER REFERENCES item(id) ON DELETE TRIGGER,  -- Next peer
  tile_id INTEGER REFERENCES tile(id) ON DELETE SET NULL,  -- NULL = no visual yet
  CHECK (id != ascn_id AND id != desc_id AND id != next_id)  -- No self-reference
  -- Note: ascn_id assigned on creation: stem.id for native, preserved for flux
);

-- Link table with integer references
CREATE TABLE link (
  id SERIAL PRIMARY KEY,  -- Auto-incrementing integer
  src_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  dst_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  CHECK (src_id != dst_id)  -- No self-links
);

-- Tile table with integer ID
CREATE TABLE tile (
  id SERIAL PRIMARY KEY,  -- Auto-incrementing integer
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  w INTEGER NOT NULL,
  h INTEGER NOT NULL,
  viewbox_x INTEGER NOT NULL DEFAULT 0,
  viewbox_y INTEGER NOT NULL DEFAULT 0,
  viewbox_zoom REAL NOT NULL DEFAULT 1.0
);
```

### Data Tables

```sql
-- Text data
CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  content TEXT NOT NULL
);

-- File data
CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  type FileType NOT NULL,
  bytea BYTEA NOT NULL -- bytea field name explicitly chosen to avoid name conflicts in clients
);

-- User data with root item reference
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL UNIQUE,  -- Auth system ID
  username TEXT NOT NULL UNIQUE,
  bio TEXT,
  head_item_id INTEGER REFERENCES item(id) ON DELETE SET NULL  -- User's tree head
);
```

### Access Control

```sql
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission PermissionType NOT NULL,
  UNIQUE(node_id, user_id)
);
```

### Type Definitions

```sql
NodeType: ENUM('text', 'file', 'user')
FileType: ENUM('png')
PermissionType: ENUM('view', 'edit', 'admin')  -- Hierarchy: view < edit < admin
```

### Indexes

```sql
-- Core indexes for traversal
CREATE INDEX index_item__ascn_id ON item(ascn_id);  -- Find native descendants
CREATE INDEX index_item__desc_id ON item(desc_id);  -- Find heads
CREATE INDEX index_item__next_id ON item(next_id);  -- Find peers
CREATE INDEX index_item__node_id ON item(node_id);  -- Find by content
CREATE INDEX index_item__root ON item(id) WHERE ascn_id IS NULL;  -- Find roots

-- Performance indexes
CREATE INDEX index_item__id__ascn_id ON item(id, ascn_id);  -- Origin chain
CREATE INDEX index_item__desc_id_not_null ON item(id) WHERE desc_id IS NOT NULL;  -- Heads
```

## Access Control

### Permission Sources
1. **Creator Permission**: Node creators automatically have admin permission (via node.creator_id)
2. **Explicit Grants**: Permissions stored in node_access table (one permission per node-user pair)
3. **Most Permissive Wins**: If multiple permission paths exist, the highest permission applies

### Flux Permission Checks
For items in flux condition (where item.ascn_id ≠ stem.id), permissions require:
```
CHECK_ACCESS(node_id, user_id, required_permission):
  1. Check direct node access (creator or explicit grant)
  2. If node is part of flux item:
     a. Check permission via stem lineage
     b. Check permission via ascendant lineage  
     c. Return TRUE only if BOTH grant required permission
  4. Return result from step 1
```

### Key Principles
- Permissions do NOT propagate to descendants
- Each node has independent access control
- Composition boundaries enforce security via dual-lineage checks
- Link permissions are derived from the source node's permissions

## Tree Mechanics

### Root: Item with ascn_id = NULL

### Item Relationships
- `ascn_id`: Points to ascendant (assigned on creation)
- `desc_id`: Points to head of branch
- `next_id`: Points to next peer in branch
- **Flux detection**: `descendant.ascn_id ≠ stem.id`

### Key Queries

#### Get Stem's Branch
```
GET BRANCH from stem:
  GET items WHERE item.ascn_id = stem.id OR item.id = stem.desc_id -- Native descendants and head (head may be in flux)
```

#### Detect Flux Points
```
DETECT FLUX:
  FROM stem s
  JOIN descendant d ON s.desc_id = d.id
  WHERE s.id ≠ d.ascn_id
```

## Traversal Algorithms

Two distinct traversal types reflect the dual lineage model:
- **Ascendant Traversal**: Following ascn_id chains (ascendant lineage)
- **Stem Traversal**: Following desc_id/next_id chains (stem lineage)

### Is Head?

```
IS HEAD(item):
  RETURN EXISTS(SELECT 1 FROM item WHERE desc_id = item.id)
```

### Ascendant Traversal (Ascendant Lineage)
Follows ascn_id relationships - the ascendant lineage:

```
UPWARD: start_id → ascn_id → ascn_id → ... → NULL

DOWNWARD: Find all with this ascendant
  GET items WHERE ascn_id = this.id
```

### Stem Traversal (Stem Lineage)
Follows desc_id/next_id relationships - the stem lineage:

```
TRAVERSE from start_id:
  FOLLOW desc_id → descendant
  FOLLOW next_id → peer
  TRACK path for cycles
  LIMIT depth < 20

DETECT flux WHERE ascn_id ≠ previous.id
```

## Advantages

1. **Normalized Structure**: Direct tree relationships without abstraction layers
2. **Fast Operations**: Ascendant lookup and tree composition are index-based
3. **Natural Composition**: Tree composition via flux detection
4. **Direct Relationships**: Ascendant-descendant relationships are explicit
5. **Dual Lineage Model**: Rich semantics with origin preservation

## Disadvantages

1. **Implicit Tree Identity**: No explicit tree container with ID
2. **Root-Based Operations**: Trees defined by shared ancestry require traversal
3. **Cycle Prevention Overhead**: Trigger validation on every ascn_id assignment

**Note on Tree Queries**: The absence of explicit tree containers naturally guides implementations toward item-focused operations rather than tree-wide operations. This architectural constraint promotes efficient, localized patterns. When tree-wide operations are needed, purpose-built functions can provide them without compromising simplicity.

## Referential Integrity Matrix

Every FK relationship must define explicit behavior.

**Note**: All IDs under our control are immutable (ON UPDATE RESTRICT). Only external auth.users.id can change, ie by db service provider, so (ON UPDATE CASCADE).

### Item Relationships
```
item.ascn_id → item.id
  ON DELETE CASCADE  -- Delete ascendant → delete native descendants
  
item.desc_id → item.id
item.next_id → item.id
  ON DELETE TRIGGER  -- Complex repointing (see Deletion Matrix)
  
item.node_id → node.id  
  ON DELETE CASCADE  -- Delete node → delete item

item.tile_id → tile.id
  ON DELETE SET NULL -- Delete tile → nullify reference
  Note: NULL tile_id = item exists but not yet visualized as tile
```

### Data Table Relationships
```
data_*.node_id → node.id
  ON DELETE CASCADE  -- Node owns data lifecycle
  Direct DELETE on data_* tables: PROHIBITED

data_user.head_item_id → item.id
  ON DELETE SET NULL -- User can exist without head
```

### Node & Access Relationships
```
node.creator_id → auth.users.id
  ON DELETE SET NULL -- Preserve nodes if creator deleted
  ON UPDATE CASCADE  -- Auth IDs can change

node_access.node_id → node.id
  ON DELETE CASCADE  -- Delete node → delete permissions

node_access.user_id → auth.users.id
  ON DELETE CASCADE  -- Delete user → delete permissions
  ON UPDATE CASCADE  -- External auth IDs can change
```

## Critical Design Decisions

### 1. Ascendant Assignment Rules
- **Root creation**: `ascn_id = NULL`
- **Native growth**: `new_item.ascn_id = stem.id`  
- **Flux composition**: `new_item.ascn_id` preserves ascendant lineage
- **Result**: Flux detectable via `stem.id != descendant.ascn_id`

### 2. Root Item Management
- Roots have `ascn_id = NULL`
- Need careful handling to prevent accidental root creation
- User workspace roots must be explicitly managed

### 3. Tree Identity Problem
Trees have implicit identity:
- Tree membership determined by shared ancestry
- Traverse from root to find all members
- Tree-level metadata can be stored on root items

## Performance Analysis

### Query Boundaries
- Max traversal depth: 20 levels (configurable)
- Statement timeout: 5s
- Work memory: 256MB for recursive queries

### Expected Performance
- **Ascendant lookup** (ascn_id): O(1), <1ms
- **Tree composition**: O(1) UPDATE, <5ms  
- **Origin chain traversal**: O(depth), ~2ms per level
- **Flux detection**: O(1) comparison, <1ms
- **Permission check**: O(depth) for both paths, <50ms typical

### Positive
- Fast ascendant lookup via ascn_id index
- Tree composition/movement are single UPDATE operations
- Efficient ancestry queries with recursive CTEs
- Natural index on ascendant-descendant relationships
- Direct pointer traversal without indirection

### Negative
- Tree membership queries require traversal (see Note on Tree Queries in Disadvantages)
- Common ancestor queries can be expensive without caching

## Implementation Challenges

1. **Ascendant Assignment**
   - Must determine ascn_id at creation time (native vs flux)
   - Ascn_id immutability must be enforced
   - Prevents cycles in ascendant chains

2. **Flux Constraints**
   - Flux items must always be heads (no next_id references)
   - Stem owns lifecycle of flux descendants
   - Requires validation on item operations

3. **User Entry Points**
   - Every user needs a root item (head_item_id)
   - Must be created automatically with user
   - Provides consistent tree entry

## Edge Cases and Resolutions

### 1. Circular Origin References
**Issue**: Item A has ascn_id→B, B has ascn_id→A
**Invariant**: I3 (Referential Integrity)
**Solution**: Trigger validation prevents cycles before commit

### 2. Origin-View Conflicts
**Issue**: Item's ascendant deleted but stem remains
**Invariant**: I5 (Dual Lineage Trees)
**Solution**: CASCADE on ascn_id removes item; view references auto-cleaned

### 3. Root Proliferation
**Issue**: Deleting items with ascn_id creates new roots
**Invariant**: I4 (Tree Traversability)
**Solution**: Intentional - orphaned branches become new trees

### 4. Composition Cycles
**Issue**: A→B→C→A creates infinite traversal loop
**Invariant**: I8 (Cycles Permitted)
**Solution**: Path tracking in traversal prevents infinite loops
**Consequences**:
- Same subtree can appear multiple times in traversal
- Depth limits become essential
- Cycle detection identifies but doesn't prevent cycles
- Enables self-referential templates and recursive structures

### 5. Cross-Tree desc_id
**Issue**: desc_id points to item in different tree
**Invariant**: I5 (Dual Lineage Trees)
**Solution**: Feature not bug - this IS composition

### 6. Double Composition
**Issue**: Item appears in multiple trees via different desc_id refs
**Invariant**: I5 (Dual Lineage Trees)
**Solution**: Supported - same item can be composed multiple times

### 7. User Workspace Management
**Issue**: User workspaces need entry points
**Invariant**: I4 (Tree Traversability)
**Solution**: data_user.head_item_id points to user's head item

### 8. Tree Identity Queries
**Issue**: No efficient "all items in tree X"
**Invariant**: Design trade-off
**Solution**: Traverse from root OR materialize paths

### 9. Deferred Visualization
**Issue**: Items may exist without visual representation
**Invariant**: Progressive enhancement
**Solution**: tile_id = NULL until frontend initializes based on context

### 10. Permission Inheritance
**Issue**: Which path determines permissions?
**Invariant**: I7 (Permission Authority)
**Solution**: Least permissive wins - must have access via BOTH paths

## Common Patterns and Solutions

### Pattern: Tree Composition
**Issue**: Need to include subtree from different tree
**Solution**: Use fn_item_compose to set desc_id to target item, maintains dual lineage
**Example**: `SELECT fn_item_compose(local_item_id, external_item_id)`

### Pattern: Tree Extraction
**Issue**: Remove composed subtree
**Solution**: Set desc_id to NULL or next valid head
**Example**: `UPDATE item SET desc_id = NULL WHERE id = mount_point_id`

### Pattern: Origin Preservation
**Issue**: Need to track where items came from
**Solution**: ascn_id chain provides complete origin history
**Example**: Recursive CTE up ascn_id finds origin root

### Pattern: Root Creation
**Issue**: Create new tree
**Solution**: Insert item with ascn_id = NULL
**Example**: `INSERT INTO item (node_id, ascn_id) VALUES (node_id, NULL)`

### Pattern: Native Growth
**Issue**: Add item to existing tree
**Solution**: Set ascn_id = stem.id for native growth
**Example**: 
```sql
-- Adding descendant to stem (native growth)
INSERT INTO item (node_id, ascn_id) 
VALUES (new_node_id, stem_item_id);

-- Then connect it
UPDATE item SET desc_id = new_item_id WHERE id = stem_item_id;
```
**Note**: Helper functions like `fn_item_add_desc()` and `fn_item_add_next()` can encapsulate ascn_id inheritance

### Pattern: Permission Checking
**Issue**: Determine access for composed items
**Solution**: Check node_access for item's node, considering flux boundaries
**Notes**:
- Simple case: Check `node_access` for `item.node_id`
- Flux consideration: May need to check both ascendant and stem lineages
- Implementation varies by security requirements
- Start simple, enhance based on actual needs


## Exclusions

### OUT OF SCOPE

- Read replicas for complex tree queries
- Caching layer for flux detection
- Mock data generation for performance testing eg `seed.sql`
- Composition metadata (who/when/why)
- Tree versioning and history
- Spatial/Geometric/x/y/viewbox indexes eg `tile.x`, `tile.y`, `tile.viewbox_x`, `tile.viewbox_y`
- Performance monitoring and query optimization tracking

## Appendices

### Alternative Architectures

- **Mount-Based** (architecture.md): Uses memo indirection for tree composition
- **Fork-Based** (architecture.forks.md): Every item carries memo_id for tree membership
- **Memo-ID Based**: Similar to fork-based but with different update semantics

This ascendant-based approach was selected for its schema simplicity and natural composition model.

### Key Trade-Offs

1. **Tree Identity vs Simplicity**
   - Lost: Explicit tree containers with IDs
   - Gained: Simpler schema, natural composition
   - Impact: Tree-wide operations require traversal

2. **Dual Traversal Complexity**
   - Cost: Two traversal patterns to understand
   - Benefit: Rich composition semantics  
   - Key distinction: Ascendant lineage (ascn_id) vs Stem lineage (desc_id)
   - Mitigation: Clear documentation, helper functions

3. **Integer IDs vs UUIDs**
   - Lost: Distributed ID generation
   - Gained: Space efficiency, simpler joins
   - Requirement: Careful sequence management

### Implementation Concerns

1. **Cycle Detection Performance**
   - Trigger validation on every ascn_id assignment
   - Consider: Deferred validation for bulk operations

2. **Permission Boundary Complexity**
   - Flux points create security boundaries
   - Solution: Start simple, enhance as needed, least permissive wins

### User Table Design Decision

**Users as data_user (chosen)** vs dedicated users table:
1. **Consistency wins**: Users follow universal node pattern, enabling user workspaces and social features
2. **Performance acceptable**: Join overhead negligible vs architectural benefits
3. **Extensibility preserved**: User relationships, metadata naturally fit node/item/link patterns
4. **Mitigation available**: If performance critical, use materialized views or caching for auth flows
