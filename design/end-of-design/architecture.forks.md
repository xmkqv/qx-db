# Dual Lineage Tree Architecture

## Invariants: Irreducible Requirements

**Terms**:
- **Invariant**: A condition that must always be true, regardless of system state
- **Root**: An item with ascn_id = NULL
- **Head**: An item referenced by any other item's desc_id (branch origin)
- **Stem**: The instantaneous parent - item whose desc_id points to a descendant
- **Ascendant**: The true parent - item referenced by ascn_id
- **Native Descendant**: Descendant where descendant.ascn_id = stem.id
- **Flux**: Discontinuity where descendant.ascn_id ≠ stem.id
- **Flux Descendant**: Descendant at a flux point, composed from another origin

### I1: Universal Node Identity
Every entity is a node with unique identity, type, and timestamps.

### I2: Data-Node Bijection
Every node has exactly one data entry. Every data entry has exactly one node.

### I3: Referential Integrity  
All pointers must reference existing entities or be null.

### I4: Tree Traversability
Every tree must be traversable from well-defined root items (ascn_id = NULL).

### I5: Dual Lineage Trees
Dual lineage tree architecture tracks two distinct lineages: `ascn_id` preserves item origin while `desc_id` defines instantaneous structure. Tree composition occurs at flux boundaries where these lineages diverge.
Tree composition is detected via flux: where descendant.ascn_id ≠ stem.id.

### I6: Lifecycle Authority
Nodes own the lifecycle of their data and connections.

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
- Flux descendants: `new_item.ascn_id` preserves original lineage
- Enables fast branch queries via ascn_id index

### P2: Flux as Feature (from I5)
- Flux points mark tree composition boundaries
- No special entities needed - discontinuity IS the marker
- Cross-tree desc_id references create flux naturally

### P3: Root Simplicity (from I4)
- Trees start at roots (ascn_id = NULL)
- No explicit containers or identity needed
- Tree membership is implicit via ancestry

### P4: Cycle Handling (from I8)
- Cycles create infinite traversal possibilities
- Path tracking prevents infinite loops
- Cycle points can be detected and reported
- Enables recursive structures (e.g., templates referencing themselves)

### P5: Simplified Lifecycle (from I6)
- Direct ascendant-descendant relationships
- Simple entity lifecycle management
- Clean deletion cascades via ascn_id

### P6: Flux-Aware Permissions (from I7)
- Native descendants inherit stem permissions naturally
- Flux descendants require checks on both lineages
- Least permissive wins at flux boundaries
- Security preserved across tree composition

## Critical Design Decisions

**Terms**:
- **Branch Head**: Item that serves as desc_id target for other items
- **Flux Point**: Where ascn_id discontinuity occurs (composition boundary)
- **Native Branch**: All descendants have continuous ascn_id lineage
- **Flux Branch**: Contains one or more flux points

### Item Deletion Trigger Logic

When deleting an item in the dual lineage model:

#### Deletion Cases Matrix

| Case | Root? | Has Native Desc? | Acts as Head? | Has Peers? | Solution |
|------|-------|-----------------|---------------|------------|----------|
| R1 | Yes | Yes | - | - | **Cascade Delete**: Native descendants deleted via CASCADE |
| R2 | Yes | No | Yes | - | **Head Repoint**: Update desc_id references to NULL |
| R3 | Yes | No | No | - | **Simple Delete**: No complications |
| N1 | No | Yes | No | No | **Native Cascade**: Descendants deleted via ascn_id CASCADE |
| N2 | No | Yes | Yes | No | **Dual Update**: Cascade natives, repoint heads |
| N3 | No | Yes | No | Yes | **Native Cascade + Splice**: Delete descendants, splice peers |
| H1 | No | No | Yes | No | **Head Repoint**: Stem's desc_id updated |
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

### Core Tables

```sql
-- Node table with auto-incrementing IDs
CREATE TABLE node (
  id SERIAL PRIMARY KEY,  -- Auto-incrementing integer
  type NodeType NOT NULL,  -- Immutable after creation
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
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
  content TEXT NOT NULL,
  tsvector tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);

-- File data
CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  type FileType NOT NULL,
  bytes INTEGER NOT NULL,
  uri TEXT NOT NULL
);

-- User data with root item reference
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL UNIQUE,  -- Auth system ID
  username TEXT NOT NULL UNIQUE,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  head_item_id INTEGER REFERENCES item(id) ON DELETE SET NULL  -- User's tree head
);

-- No additional tree container tables needed
```

### Access Control

```sql
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission PermissionType NOT NULL,
  granted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  UNIQUE(node_id, user_id)
);

CREATE TABLE link_access (
  id SERIAL PRIMARY KEY,
  link_id INTEGER NOT NULL REFERENCES link(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission PermissionType NOT NULL,
  UNIQUE(link_id, user_id)
);
```

### Type Definitions

```sql
NodeType: ENUM('text', 'file', 'user')
FileType: ENUM('png', 'jpg', 'pdf', 'mp4', 'json')
PermissionType: ENUM('view', 'edit', 'admin')
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

## Tree Mechanics

### Root Detection
An item is a root when `ascn_id IS NULL`.

### Item Relationships
- `ascn_id`: Points to ascendant (assigned on creation)
- `desc_id`: Points to head of descendant branch
- `next_id`: Points to next peer in current branch
- **Flux detection**: `descendant.ascn_id ≠ stem.id`

### Key Queries

#### Get Direct Descendants (Branch Query)
```sql
-- Fast lookup via ascn_id index
SELECT * FROM item WHERE ascn_id = stem_item.id;
```

#### Detect Flux Points
```sql
-- Find all flux descendants of an item
SELECT d.* 
FROM item s  -- stem
JOIN item d ON s.desc_id = d.id  -- descendant
WHERE s.id != d.ascn_id;  -- flux detected!
```

#### Get Native Branch
```sql
-- Get all native descendants
SELECT * FROM item WHERE ascn_id = stem_item.id;

## Tree Composition

### Natural Composition
Tree composition happens when desc_id crosses ancestry boundaries.

#### Example: Composing Document into Folder

Initial state:
```
Folder Tree:                         Document Tree:
A[ascn=NULL]                         D[ascn=NULL]
└── B[ascn=A]                        └── E[ascn=D]
    └── C[ascn=B]                        └── F[ascn=E]
```

Composition operation:
```sql
-- Compose document tree under item C
UPDATE item SET desc_id = 'D' WHERE id = 'C';
```

Result with flux detection:
```
Visual Tree:                         Flux Analysis:
A                                    
└── B                                B → C: Native (C.ascn = B)
    └── C                            C → D: FLUX! (D.ascn ≠ C)
        └── D                        D → E: Native (E.ascn = D)
            └── E                    E → F: Native (F.ascn = E)
                └── F
```

Query to find flux:
```sql
-- Returns D as flux descendant of C
SELECT d.* FROM item c
JOIN item d ON c.desc_id = d.id
WHERE c.id != d.ascn_id;  -- C != D.ascn (NULL)
```

### Flux Detection Patterns

```sql
-- Simple flux detection at any point
SELECT s.id as stem_id, d.id as flux_desc_id
FROM item s
JOIN item d ON s.desc_id = d.id
WHERE s.id != d.ascn_id;

-- Find all flux points in a tree
WITH RECURSIVE tree AS (
  SELECT id, ascn_id, desc_id, 0 as depth
  FROM item WHERE id = root_id
  UNION ALL
  SELECT i.id, i.ascn_id, i.desc_id, t.depth + 1
  FROM item i
  JOIN tree t ON i.ascn_id = t.id OR t.desc_id = i.id
)
SELECT t1.id as stem, t2.id as flux_point
FROM tree t1
JOIN tree t2 ON t1.desc_id = t2.id
WHERE t1.id != t2.ascn_id;
```

## Traversal Algorithms

Two distinct traversal types reflect the dual lineage model:
- **Ascendant Traversal**: Following ascn_id chains (true lineage)
- **Stem Traversal**: Following desc_id/next_id chains (instantaneous structure)

### Ascendant Traversal (Origin Lineage)
Follows ascn_id relationships - the true parent chain:

```sql
-- Upward: Find origin ancestors
WITH RECURSIVE ascendant_chain AS (
  SELECT * FROM item WHERE id = start_id
  UNION ALL
  SELECT i.* FROM item i
  JOIN ascendant_chain a ON i.id = a.ascn_id
)
SELECT * FROM ascendant_chain;

-- Downward: Find native descendants of this item
SELECT * FROM item WHERE ascn_id = item_id;  -- Fast via index
```

### Stem Traversal (Composed Structure)
Follows desc_id/next_id relationships - the instantaneous parent chain:

```sql
-- Full tree traversal
WITH RECURSIVE stem_tree AS (
  SELECT *, 0 as depth, ARRAY[id] as path
  FROM item WHERE id = start_id
  
  UNION ALL
  
  SELECT i.*, f.depth + 1, f.path || i.id
  FROM item i
  JOIN stem_tree s ON s.desc_id = i.id  -- Stem to descendant
                   OR s.next_id = i.id  -- Peer to peer
  WHERE NOT (i.id = ANY(f.path))  -- Cycle prevention
  AND f.depth < 20
)
SELECT * FROM stem_tree;

-- Detect flux points during traversal
SELECT f.*, 
       CASE WHEN f.ascn_id != LAG(f.id) OVER (ORDER BY path) 
            THEN true ELSE false END as is_flux
FROM flux_tree f;
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

**Note on Tree Queries**: The absence of explicit tree containers naturally guides implementations toward item-focused operations rather than tree-wide operations. This architectural constraint promotes efficient, localized patterns. When tree-wide operations are needed, purpose-built functions can provide them without compromising the core simplicity.

## Referential Integrity Matrix

Every FK relationship must define explicit behavior.

**Note**: All IDs under our control are immutable (ON UPDATE RESTRICT). Only external auth.users.id can change (ON UPDATE CASCADE).

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
- **Flux composition**: `new_item.ascn_id` preserves original value
- **Result**: Flux detectable via `stem.id != descendant.ascn_id`

### 2. Root Item Management
- Roots have ascn_id = NULL
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

## Comparison with Other Approaches

### Mount-Based (Current)
- **Pros**: Explicit tree identity, efficient tree queries, clear separation
- **Cons**: Indirection complexity, mount resolution overhead, extra entities

### Memo-ID Based (Alternative)
- **Pros**: Direct tree membership, set operations on trees
- **Cons**: Redundant memo_id on every item, complex updates

## Implementation Challenges

1. **Migration Complexity**
   - Must establish ascn_id for all existing items
   - Convert existing tree relationships to ascendant model
   - Update user entry points

2. **Tree Operations**
   - All operations are single UPDATE statements (see Common Patterns)
   - ascn_id immutability preserves origin through all moves

3. **Cycle Prevention**
   ```sql
   CREATE OR REPLACE FUNCTION func_item_prevent_ascn_cycles()
   RETURNS TRIGGER AS $$
   DECLARE
     current_id INTEGER := NEW.ascn_id;
   BEGIN
     WHILE current_id IS NOT NULL LOOP
       IF current_id = NEW.id THEN
         RAISE EXCEPTION 'Ascendant cycle detected';
       END IF;
       SELECT ascn_id INTO current_id FROM item WHERE id = current_id;
     END LOOP;
     RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;
   
   CREATE TRIGGER check_ascn_cycles
     BEFORE INSERT OR UPDATE ON item
     FOR EACH ROW
     EXECUTE FUNCTION func_item_prevent_ascn_cycles();
   ```

4. **Branch Root Validation**
   ```sql
   CREATE OR REPLACE FUNCTION func_item_validate_desc_head()
   RETURNS TRIGGER AS $$
   BEGIN
     IF NEW.desc_id IS NOT NULL THEN
       -- Check if target is a head (no incoming next_id)
       IF EXISTS (SELECT 1 FROM item WHERE next_id = NEW.desc_id) THEN
         RAISE EXCEPTION 'desc_id must point to a head (item with no incoming next_id)';
       END IF;
     END IF;
     RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;
   
   CREATE TRIGGER check_desc_id_branch_root
     BEFORE INSERT OR UPDATE ON item
     FOR EACH ROW
     WHEN (NEW.desc_id IS DISTINCT FROM OLD.desc_id)
     EXECUTE FUNCTION func_item_validate_desc_head();
   ```

5. **User Workspace Creation**
   ```sql
   CREATE OR REPLACE FUNCTION func_user_create_head_item()
   RETURNS TRIGGER AS $$
   DECLARE
     head_node_id INTEGER;
     head_item_id INTEGER;
   BEGIN
     IF NEW.head_item_id IS NULL THEN
       -- Create node for head item
       INSERT INTO node (type) VALUES ('text')
       RETURNING id INTO head_node_id;
       
       -- Create head item (ascn_id = NULL for roots)
       INSERT INTO item (node_id, ascn_id) 
       VALUES (head_node_id, NULL)
       RETURNING id INTO head_item_id;
       
       -- Update user with head item
       NEW.head_item_id := head_item_id;
     END IF;
     RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;
   
   CREATE TRIGGER ensure_user_has_head
     BEFORE INSERT ON data_user
     FOR EACH ROW
     EXECUTE FUNCTION func_user_create_head_item();
   ```

6. **Ascendant Immutability**
   ```sql
   CREATE OR REPLACE FUNCTION func_item_enforce_ascn_immutability()
   RETURNS TRIGGER AS $$
   BEGIN
     IF OLD.ascn_id IS DISTINCT FROM NEW.ascn_id THEN
       RAISE EXCEPTION 'ascn_id is immutable after creation';
     END IF;
     RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;
   
   CREATE TRIGGER protect_ascn_id
     BEFORE UPDATE ON item
     FOR EACH ROW
     EXECUTE FUNCTION func_item_enforce_ascn_immutability();
   ```

## Edge Cases and Resolutions

### 1. Circular Origin References
**Issue**: Item A has ascn_id→B, B has ascn_id→A
**Invariant**: I3 (Referential Integrity)
**Solution**: Trigger validation prevents cycles before commit

### 2. Origin-View Conflicts
**Issue**: Item's ascendant deleted but stem remains
**Invariant**: I5 (Dual Parentage)
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
**Issue**: desc_id points to item in different origin tree
**Invariant**: I5 (Dual Parentage)
**Solution**: Feature not bug - this IS composition

### 6. Double Composition
**Issue**: Item appears in multiple trees via different desc_id refs
**Invariant**: I5 (Dual Parentage)
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
**Issue**: Need to include subtree from another origin
**Solution**: Set desc_id to target item, maintains dual lineage
**Example**: `UPDATE item SET desc_id = foreign_item_id WHERE id = local_item_id`

### Pattern: Tree Extraction
**Issue**: Remove composed subtree
**Solution**: Set desc_id to NULL or next valid branch root
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
**Note**: Helper functions like `item_add_desc()` and `item_add_next()` can encapsulate ascn_id inheritance

### Pattern: Permission Checking
**Issue**: Determine access for composed items
**Solution**: Check node_access for item's node, considering flux boundaries
**Notes**:
- Simple case: Check `node_access` for `item.node_id`
- Flux consideration: May need to check both origin and view paths
- Implementation varies by security requirements
- Start simple, enhance based on actual needs

## Alternative Architectures Explored

- **Mount-Based** (architecture.md): Uses memo indirection for tree composition
- **Fork-Based** (architecture.forks.md): Every item carries memo_id for tree membership
- **Memo-ID Based**: Similar to fork-based but with different update semantics

This ascendant-based approach was selected for its schema simplicity and natural composition model.

## Concerns, Trade-Offs, and Future Work

### Key Trade-Offs

1. **Tree Identity vs Simplicity**
   - Lost: Explicit tree containers with IDs
   - Gained: Simpler schema, natural composition
   - Impact: Tree-wide operations require traversal

2. **Dual Traversal Complexity**
   - Cost: Two traversal patterns to understand
   - Benefit: Rich composition semantics  
   - Key distinction: Ascendant = true parent (ascn_id), Stem = instantaneous parent (desc_id)
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
   - Solution: Start simple, enhance as needed
   
3. **Missing Helper Functions**
   - Native growth requires manual ascn_id management
   - Plan: `item_add_desc()`, `item_add_next()` functions

### Future Optimizations

**When Scale Demands:**
- Materialized paths for hot traversal routes
- Partial indexes on common query patterns
- Read replicas for complex tree queries
- Caching layer for flux detection

**Possible Extensions:**
- Composition metadata (who/when/why)
- Tree versioning and history
- Multi-ascendant support (DAG structure)
- Bulk tree operations

### Deferred Decisions

1. **Permission Model Details**: Origin-only, view-only, or both?
2. **Tree Enumeration**: How to efficiently list all trees?
3. **Migration Tooling**: From mount-based architecture
4. **Adoption Semantics**: Should ascn_id ever be mutable?