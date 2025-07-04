# qx-db Architecture

## Core Invariants

**Terms**:
- **Invariant**: A condition that must always be true, regardless of system state
- **Bijection**: One-to-one correspondence between sets (every A has exactly one B)
- **Tree**: A hierarchical structure that can be composed into other trees
- **Node**: Universal entity with identity, type, and timestamps

**Format Convention**:
- **Issue**: Specific problem or constraint
- **Invariant**: Which core invariant addresses this
- **Solution**: How the system maintains the invariant

The minimal, irreducible set of requirements that define the system:

### I1: Universal Node Identity
Every entity is a node with unique identity, type, and timestamps.

### I2: Data-Node Bijection
Every node has exactly one data entry. Every data entry has exactly one node.

### I3: Referential Integrity  
All pointers must reference existing entities or be null.

### I4: Tree Traversability
Every tree must be traversable from a well-defined entrypoint.

### I5: Tree Composition
Same node can appear in multiple tree positions through memo indirection.

### I6: Lifecycle Authority
Nodes own the lifecycle of their data and connections.

### I7: Permission Authority
Nodes are the authoritative source for all access control, enabling tree traversal even without data access.

## Design Principles

**Terms**:
- **Reverse Ownership**: Child references parent, not parent referencing children
- **Polymorphic Nodes**: Single node type with data stored in type-specific tables
- **Memo Indirection**: Pattern where memos act as mount points for trees
- **ON DELETE CASCADE**: When row in referenced table deleted, delete row in referencing table

Derived from invariants, these guide all implementation decisions:

### P1: Reverse Ownership (from I2, I6)
- Data tables reference nodes via `node_id` FK with ON DELETE CASCADE
- Direct INSERT/DELETE on data tables prohibited via triggers
- When node deleted, cascade flows: referenced (node) → referencing (data_*)

### P2: Polymorphic Nodes (from I1, I2)
- Node type discriminates which `data_*` table contains content
- Deferred constraint ensures node-data bijection
- Type immutability after creation

### P3: Dual Connection Model (from I5)
- `item`: Tree structure via desc_id/next_id pointers
- `link`: Semantic relationships via src_id/dst_id

### P4: Memo Indirection (from I4, I5)
- `data_memo` contains tree entry points
- Mount pattern enables tree composition
- Cycles permitted but detected during traversal

### P5: Constraint-Based Integrity (from I3)
- Foreign keys prevent dangling references
- Check constraints prevent self-reference
- Triggers maintain pointer consistency
- Every FK relationship must define ON DELETE behavior

### P6: Permission Inheritance (from I7)
- Trees derive base permissions from their memo container
- Individual items can override with specific node permissions
- Tree structure remains traversable even without data access
- Node-based ACL enables phantom item traversal

## Critical Design Decisions

**Terms**:
- **Item**: A position in the tree hierarchy with desc_id and next_id pointers
- **Branch**: Chain of items connected by next_id pointers
- **Branch Root**: First item in a branch (no predecessor via next_id)
- **Stem**: Item whose desc_id points to a branch
- **Peers**: Items within same branch, connected via next_id
- **Mount**: Item that points to a node of type='memo', used to mount trees
- **desc_id**: Pointer to first descendant (starts new branch)
- **next_id**: Pointer to next peer (continues current branch)

### Tree Composition via Memo Indirection

The fundamental challenge: How to compose entire trees as units within other trees while maintaining tree properties?

#### The Problem
Tree composition differs from simple node reuse:
- **Node reuse**: Same data appears in multiple locations
- **Tree composition**: Entire subtree embedded as a unit

Requirements for composable trees:
- **Unit behavior**: Tree maintains its internal structure
- **Addressability**: Can reference the tree as a whole
- **Distinguishability**: Clear boundaries between tree and mounted subtrees
- **Traversability**: Seamless navigation across tree boundaries

Classical approaches (mount points, modules, namespaces) provide partial solutions but we need:
- Dynamic composition without static configuration
- Multiple inclusions of same tree
- Preservation of internal tree relationships

Theoretical foundation: Similar to UNIX mount points but for tree structures, allowing dynamic binding of entire subtrees at arbitrary positions.

#### The Solution: Mount Pattern

Memos provide the unit abstraction for composable trees:

```
Tree as unit:
  memo[id=X] contains tree starting at item2
  
Mounting the unit:
  item1 --desc_id--> mount[node=X] --[resolve]--> memo[X].desc_id --> item2
```

Key properties:
1. **Unit identity**: Each memo has a unique node ID, making the tree addressable
2. **Clear boundaries**: Memo marks where subtree begins
3. **Indirection**: Mount items redirect to memo's tree without copying
4. **Preserved structure**: Subtree within memo maintains all internal relationships

#### Composition Rules

1. **Memo as Tree Container**:
   - Memo node serves as named container for a tree
   - Contains tree via desc_id (see Mount Resolution)
   - Tree becomes a referenceable unit with identity

2. **Tree Mounting**:
   - Create mount (see definition)
   - Mount establishes connection point between trees
   - Traversal crosses boundary transparently

3. **Cycle Detection**:
   - Track item.id path during traversal
   - If revisiting item.id, mark as cycle
   - Continue traversal but skip revisited branch

4. **Permission Boundaries**:
   - Memo node provides base permissions for entire tree
   - Items within tree can have additional permissions via their nodes
   - Phantom traversal
   - Permission checks cascade: memo permissions + item permissions

### Item Deletion Trigger Logic

Maintains tree structure integrity when items are deleted by repointing connections.

#### Deletion Cases Matrix

| Case | Branch Root? | Has Peers? | Has Descendants? | Memo Entry? | Solution |
|------|-------------|------------|------------------|-------------|----------|
| M1 | - | Yes | - | Yes | **Memo Peer Promotion**: Update memo.desc_id → next_id |
| M2 | - | No | Yes | Yes | **Memo Descendant Promotion**: Update memo.desc_id → desc_id |
| M3 | - | No | No | Yes | **Memo Emptying**: Update memo.desc_id → NULL |
| B1 | Yes | Yes | No | No | **Branch Peer Promotion**: Update stem.desc_id → next_id |
| B2 | Yes | No | Yes | No | **Branch Descendant Promotion**: Update stem.desc_id → desc_id |
| B3 | Yes | No | No | No | **Branch Termination**: Update stem.desc_id → NULL |
| P1 | No | Yes | No | No | **Peer Splice**: Update predecessor.next_id → next_id |
| P2 | No | No | Yes | No | **Descendant Uplift**: Update predecessor.next_id → desc_id |
| P3 | No | No | No | No | **Chain Termination**: Update predecessor.next_id → NULL |
| ERR | No | Yes | Yes | No | **BLOCKED**: Cannot orphan descendants (Exception raised) |

#### Named Solutions

**Memo Operations** (M1-M3):
- Promote next available item to memo.desc_id (see Mount Resolution)
- Allow memos to become empty when no items remain

**Branch Operations** (B1-B3):
- Find stem
- Repoint stem to next available item in deleted item's position

**Peer Operations** (P1-P3):
- Find predecessor (item whose next_id points to deleted item)
- Splice out deleted item by updating predecessor's pointer

**Error Prevention**:
- Block deletion of non-root items with both peers and descendants
- This prevents orphaned branches which would violate tree properties

### Node Deletion Cascades

When a node is deleted:
1. All items referencing this node are deleted (FK CASCADE)
2. Each item deletion triggers the above logic
3. All data_* entries are deleted (FK CASCADE)
4. All links from/to this node are deleted (FK CASCADE)
5. All access grants are deleted (FK CASCADE)

### Mount Resolution

```
item1                    mount[node=memo]           memo.desc_id
  |                           |                          |
  +------- desc_id ---------> * ----[resolve]---------> item2
                              |                          |
                         node.type='memo'          (tree entry point)
                              |
                         data_memo lookup
```

**Resolution flow**:
1. Check if item's node has type='memo'
2. If memo: lookup data_memo.desc_id → jump to tree entry point
3. If not memo: continue with current item
4. Empty memos (desc_id=NULL) terminate traversal

### Tree Traversal

**Method**: `traverse_with_mounts(start_id, max_depth=20)`

**Key behaviors**:
- Depth-first traversal following desc_id then next_id
- Transparent mount resolution (see Mount Resolution)
- Path tracking prevents infinite loops from cycles
- Returns items with depth and cycle/truncation markers
- Maximum depth of 20 levels (configurable)

### Permission Boundaries

**Method**: `authorized_traverse(user_id, start_id)`

**Phantom Traversal**: Tree structure remains visible even without data access
- Items with permission: Full data returned
- Items without permission: Structure only (phantom items)
- Permission check: node.creator_id OR node_access entry
- Enables navigation through restricted areas to reach accessible content

## Schema Definitions

**Terms**:
- **Foreign Key (FK)**: Database constraint linking tables via shared values
- **Referencing Table**: The table containing the foreign key (FK holder)
- **Referenced Table**: The table containing the primary key being referenced
- **Primary Key**: Unique identifier for each row in a table
- **UNIQUE Constraint**: Ensures no duplicate values in specified columns
- **CHECK Constraint**: Validates data meets specified conditions
- **Index**: Database structure for faster data retrieval
- **ON DELETE SET NULL**: When row in referenced table deleted, set FK to NULL in referencing table
- **ON DELETE RESTRICT**: When row in referenced table has references, prevent deletion

### Core Tables

```sql
CREATE TABLE node (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type NodeType NOT NULL,  -- Immutable after creation
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE TABLE item (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  desc_id UUID REFERENCES item(id) ON DELETE TRIGGER,  -- See: Item Deletion Trigger Logic
  next_id UUID REFERENCES item(id) ON DELETE TRIGGER,  -- See: Item Deletion Trigger Logic
  tile_id UUID REFERENCES tile(id) ON DELETE SET NULL,
  CHECK (id != desc_id AND id != next_id),  -- No self-reference
  -- Note: desc_id must point to branch roots on creation (items where no other item.next_id = target.id)
);

CREATE TABLE link (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  src_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  dst_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  CHECK (src_id != dst_id)  -- No self-links
);

CREATE TABLE tile (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

Each follows reverse ownership pattern:

```sql
CREATE TABLE data_text (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  tsvector tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

CREATE TABLE data_file (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  type FileType NOT NULL,
  bytes INTEGER NOT NULL,
  uri TEXT NOT NULL
);

CREATE TABLE data_user (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL UNIQUE,  -- Auth system ID
  username TEXT NOT NULL UNIQUE,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  memo_id UUID NOT NULL REFERENCES node(id) ON DELETE RESTRICT  -- User's workspace
);

CREATE TABLE data_memo (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  desc_id UUID REFERENCES item(id) ON DELETE SET NULL  -- Tree entry point
);
```

### Access Control

```sql
CREATE TABLE node_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  node_id UUID NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission PermissionType NOT NULL,
  granted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  UNIQUE(node_id, user_id)
);

CREATE TABLE link_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id UUID NOT NULL REFERENCES link(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission PermissionType NOT NULL,
  UNIQUE(link_id, user_id)
);
```

## Type Definitions

```sql
NodeType: ENUM('text', 'file', 'user', 'memo')
FileType: ENUM('png', 'jpg', 'pdf', 'mp4', 'json')
PermissionType: ENUM('view', 'edit', 'admin')
```

## Common Patterns and Solutions

Recurring issues mapped to invariants with consistent solutions:

### Pattern: Preventing Deletion
**Issue**: Entity cannot be deleted while dependencies exist
**Invariant**: I3 (Referential Integrity)
**Solution**: ON DELETE RESTRICT on FK
**Examples**:
- `data_user.memo_id → node.id` - Cannot delete user's workspace

### Pattern: Cascading Deletion
**Issue**: Dependent entities must be removed with parent
**Invariant**: I6 (Lifecycle Authority)
**Solution**: ON DELETE CASCADE on FK (deletes referencing when referenced deleted)
**Examples**:
- `data_*.node_id → node.id` - Node owns data lifecycle
- `item.node_id → node.id` - Node owns all positions
- `link.src_id/dst_id → node.id` - Node owns relationships
- `node_access.node_id → node.id` - Node owns permissions

### Pattern: Orphaning Allowed
**Issue**: Parent deletion should not delete dependent
**Invariant**: Context-specific
**Solution**: ON DELETE SET NULL on FK
**Examples**:
- `node.creator_id → user.id` - Preserve nodes if creator deleted
- `item.tile_id → tile.id` - Items can exist without tiles
- `data_memo.desc_id → item.id` - Memos can be empty

### Pattern: Complex Repointing
**Issue**: Tree structure must remain valid after deletion
**Invariant**: I4 (Tree Traversability)
**Solution**: ON DELETE TRIGGER with repointing logic (see: Item Deletion Trigger Logic)
**Examples**:
- `item.desc_id/next_id → item.id` - Maintain tree connectivity

### Pattern: Immutable References
**Issue**: IDs should never change after creation
**Invariant**: I3 (Referential Integrity)
**Solution**: ON UPDATE RESTRICT on FK
**Examples**:
- All references to `node.id` - Node IDs immutable
- All references to `item.id` - Item IDs immutable
- All references to `link.id` - Link IDs immutable
- All references to `tile.id` - Tile IDs immutable

### Pattern: Mutable External IDs
**Issue**: Auth system IDs may change
**Invariant**: External system integration
**Solution**: ON UPDATE CASCADE on FK
**Examples**:
- All references to `auth.users.id` - Track auth system changes

### Pattern: Prohibited Operations
**Issue**: Certain operations violate invariants
**Invariant**: Various
**Solution**: BEFORE triggers that raise exceptions
**Examples**:
- Direct DELETE on `data_*` tables - Violates I6
- UPDATE `node.type` - Violates I2 (bijection)
- Self-reference in `item` or `link` - Violates tree properties

## Referential Integrity Matrix

Every FK relationship must define explicit behavior. Here's the complete matrix:

### Node Relationships (Lifecycle Owner)
```
data_*.node_id → node.id
  ON DELETE CASCADE  -- Delete referenced node → delete referencing data_* rows
  ON UPDATE RESTRICT -- Node IDs immutable
  Direct DELETE on data_* tables: PROHIBITED (trigger enforced)

item.node_id → node.id  
  ON DELETE CASCADE  -- Delete referenced node → delete referencing items
  ON UPDATE RESTRICT -- Node IDs immutable

link.src_id → node.id
link.dst_id → node.id
  ON DELETE CASCADE  -- Delete referenced node → delete referencing links
  ON UPDATE RESTRICT -- Node IDs immutable

node_access.node_id → node.id
  ON DELETE CASCADE  -- Delete referenced node → delete referencing permissions
  ON UPDATE RESTRICT -- Node IDs immutable
```

### Item Relationships (Tree Structure)
```
item.desc_id → item.id
item.next_id → item.id
  ON DELETE TRIGGER  -- Delete referenced item → complex repointing (see: Item Deletion Trigger Logic)
  ON UPDATE RESTRICT -- Item IDs immutable
  
item.tile_id → tile.id
  ON DELETE SET NULL -- Delete referenced tile → set NULL in referencing item
  ON UPDATE RESTRICT -- Tile IDs immutable

data_memo.desc_id → item.id
  ON DELETE SET NULL -- Delete referenced item → set NULL in referencing memo
  ON UPDATE RESTRICT -- Item IDs immutable
```

### Access Control Relationships
```
link_access.link_id → link.id
  ON DELETE CASCADE  -- Delete referenced link → delete referencing permissions
  ON UPDATE RESTRICT -- Link IDs immutable

node_access.user_id → auth.users.id
link_access.user_id → auth.users.id
node_access.granted_by → auth.users.id
  ON DELETE CASCADE  -- Delete referenced user → delete referencing permissions/grants
  ON UPDATE CASCADE  -- User IDs can change (auth system)
```

### User Relationships
```
data_user.user_id → auth.users.id
  ON DELETE CASCADE  -- Delete referenced auth user → delete referencing profile
  ON UPDATE CASCADE  -- User IDs can change (auth system)
  
data_user.memo_id → node.id
  ON DELETE RESTRICT -- Cannot delete referenced node if referencing user exists
  ON UPDATE RESTRICT -- Node IDs immutable
  Enforced: Referenced node must be type='memo' (see: User Workspace Creation)
```

### Creator Tracking
```
node.creator_id → auth.users.id
  ON DELETE SET NULL -- Delete referenced user → set NULL in referencing node
  ON UPDATE CASCADE  -- User IDs can change (auth system)
```

## Constraint Enforcement

### Node-Data Bijection

```
Constraint: Every node must have exactly one data entry
Enforcement: Deferred trigger after node insert
Action: Verify node exists in one of: data_text, data_file, data_user, data_memo
```

### Item Pointer Consistency

```
Constraint: Tree structure must remain valid after item deletion
Enforcement: Before delete trigger on item
Action: Execute complex repointing logic (see Item Deletion Trigger Logic)
```

### User Workspace Creation

```
Constraint: Every user must have a memo workspace
Enforcement: Before insert trigger on data_user
Action: Auto-create memo node if memo_id is null
```

### Prohibited Operations

These operations are blocked at the database level:

```
1. Direct DELETE on data_* tables
   → Trigger blocks with exception
   
2. UPDATE node.type
   → Trigger blocks type changes (immutable)
   
3. Self-reference in item (id = desc_id or next_id)
   → Check constraint prevents
   
4. Self-reference in link (src_id = dst_id)
   → Check constraint prevents
   
5. Delete user's workspace memo
   → FK RESTRICT on data_user.memo_id prevents
```

## Edge Cases and Resolutions

**Terms**:
- **Last-write-wins**: Conflict resolution where most recent update prevails
- **Optimistic Locking**: Assumes conflicts are rare, checks at commit time
- **Path Tracking**: Recording visited nodes to detect cycles
- **Wild Nodes**: Nodes without any items referencing them
- **Orphaned**: Entity left without required parent/reference

### 1. Concurrent Item Modifications
**Issue**: Two users modify same item's pointers simultaneously
**Invariant**: I3 (Referential Integrity)
**Solution**: Last-write-wins with optimistic locking via updated_at

### 2. Circular Memo References
**Issue**: Memo A includes Memo B which includes Memo A
**Invariant**: I4 (Tree Traversability)
**Solution**: Path tracking in traversal detects and breaks cycles

### 2a. Deep Memo Nesting
**Issue**: Memo A → Memo B → Memo C → ... → Memo Z
**Invariant**: I4 (Tree Traversability)
**Solution**: Each memo jump counts toward depth limit

### 2b. Multiple Mounts
**Issue**: Same memo mounted multiple times in one tree
**Invariant**: I5 (Tree Composition)
**Solution**: Each mount point is independent, may traverse same content multiple times

### 2c. Mount Deletion
**Issue**: Delete mount item while memo still has content
**Invariant**: I5 (Tree Composition)
**Solution**: Only unmounts from that location, memo and its tree remain intact

### 2d. Memo Entry Point Change
**Issue**: Update data_memo.desc_id while mounts exist
**Invariant**: I5 (Tree Composition)
**Solution**: All mounts immediately point to new tree on next traversal

### 3. Orphaned Branches
**Issue**: Deleting item with descendants and peers
**Invariant**: I4 (Tree Traversability)
**Solution**: Trigger prevents this state - must delete descendants first

### 4. Empty Memos
**Issue**: All items in a memo's tree are deleted
**Invariant**: I5 (Tree Composition)
**Solution**: Memo remains with null desc_id, can be repopulated

### 5. Deep Recursion
**Issue**: Deeply nested trees exceed query limits
**Invariant**: I4 (Tree Traversability)
**Solution**: Hard depth limit (20) with truncation marker

### 6. Permission Gaps in Tree Traversal
**Issue**: User has permission to view parent item but not child item's data
**Invariant**: I7 (Permission Authority)
**Solution**: Phantom traversal

### 7. Tile Orphaning
**Issue**: Item deleted but tile remains
**Invariant**: Context-specific (tiles are independent)
**Solution**: Tiles have independent lifecycle, can be reused

### 8. Type Mismatches
**Issue**: Node type doesn't match data table
**Invariant**: I2 (Data-Node Bijection)
**Solution**: Trigger validates on data insert

### 9. Wild Nodes
**Issue**: Node exists without any items referencing it
**Invariant**: Explicitly allowed (nodes are independent entities)
**Solution**: No constraint - nodes can exist independently

### 10. Broken Chains
**Issue**: Item's next_id points to deleted item
**Invariant**: I3 (Referential Integrity)
**Solution**: FK ON DELETE TRIGGER updates pointer

## Performance Considerations

**Terms**:
- **Work Memory**: RAM allocated for query operations like sorting
- **Statement Timeout**: Maximum time allowed for a single query
- **Materialized Paths**: Pre-computed full paths stored as columns
- **Read Replicas**: Database copies for distributing read load
- **Partitioning**: Splitting large tables into smaller chunks

### Query Boundaries
- Max depth: 20 levels
- Max branch size: 1000 items
- Statement timeout: 5s
- Work memory: 256MB for recursive queries

### Index Strategy
- item(desc_id) - Find children
- item(next_id) - Find peers
- item(node_id) - Find by content
- node_access(user_id, node_id) - Permission checks
- data_*(node_id) - Reverse lookup

### Optimization Triggers
When to consider advanced optimizations:
- >10M nodes: Partitioning by workspace
- >100K concurrent users: Read replicas
- >1000 items per branch: Materialized paths
- >50ms tree queries: Redis cache

## Failure Recovery

### Transaction Rollback
All modifications wrapped in transactions. On failure:
1. All changes revert
2. Pointers remain consistent
3. No partial updates possible

### Constraint Violations
Schema constraints prevent invalid states:
- FK violations → Operation rejected
- Check violations → Operation rejected
- Unique violations → Operation rejected
- Trigger exceptions → Transaction rolled back

### Query Timeouts
Long-running queries terminated cleanly:
- Partial results not returned
- Path state not corrupted
- Client retries with smaller scope

## Future Considerations

### Not Yet Implemented
- Soft delete with audit trail
- Versioning and history
- Full-text search across trees
- Batch operations API
- Materialized path caching

### Explicitly Deferred
- Sharding strategy
- Archive policies
- Data compression
- Subscription mechanisms
- Real-time collaboration