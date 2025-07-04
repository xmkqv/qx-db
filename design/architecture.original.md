# qx-db Architecture

## Glossary

- **Node**: Base entity with id, type, timestamps
- **Data* Tables**: Stores type-specific content, linked to nodes
  - Examples: `data_text`, `data_file`, `data_user`
- **Item**: Tree position (multiple items can reference same node)
  - `desc_id`: Points to first branch item
  - `next_id`: Points to next branch item
  - `node_id`: References the node
  - `tile_id`: References a tile for render
- **Memo Proxy**: An item whose node.type='memo', used to mount a memo's treelet into another tree
- **Link**: Directed edge between nodes (unidirectional)
- **Data Memo**: Container for treelets, enables tree composition via indirection
  - Which Allows same node to appear in multiple tree positions
  - **Indirection**: For treelet mounting via a Memo Proxy: `item` (Memo Proxy) -> `node` - is memo? > `data_memo` -> `item` -> ...
- **Wild**: Node without item
- **Treelet**: A collection of items connected by next_id/desc_id relationships, contained within a memo
- **Cascade Delete**: "ON DELETE [of foreign key] CASCADE [to me]"
- **Item**:
  - A tree position in the item hierarchy, which can be a descendent of another item or a data_memo.
  - `desc_id`: Points to the first item in the branch (the root of the branch).
  - `next_id`: Points to the next item in the branch.
  - `node_id`: References the node that this item belongs to.
  - `tile_id`: References a tile for rendering purposes.
  - Stem: term used to refer to the parent item of a branch
  - Branch: term used to refer to the items that are connected via `next_id` pointers, originating from a Branch Root
  - Branch Root: term used to refer to the item that is the root of a branch, which has a `desc_id` pointing to it. It is the first item in the branch and can have multiple items after it in the branch, connected via `next_id` pointers
  - Peers: term used to refer to items that are at the same level in the hierarchy, connected via `next_id` pointers, equivalent to siblings in a tree structure. Also conceptually equivalent to a Branch except that peers usually used to refer to other items at the same level in the hierarchy, while branch is used to refer to the items in the next level down the hierarchy from the Stem.

## Design

### Reverse Ownership Architecture

Node exists before data, with strict referential integrity:
- Data tables reference nodes via FK with CASCADE DELETE
- Direct INSERT/DELETE on data tables prohibited
- All data manipulation flows through node operations

## Invariants + Maxims

- **Nodes are Universal Entities**: Nodes are the source of auth, data, and connections
    - `link.node_id FK node.id` ON DELETE CASCADE
    - `data_*.node_id FK node.id` ON DELETE CASCADE
    - `item.node_id FK node.id` ON DELETE CASCADE
      - `tile.item_id FK item.id` ON DELETE CASCADE (reverse ownership)
      - Trigger Item Delete:
        - if `get_item(next_id = item.id) === null` (ie is branch root)
          - `next_id == null` and `desc_id == null`
            - ...
          - `next_id != null` and `desc_id == null`
            - ...
          - `next_id == null` and `desc_id != null`
            - ...
          - `next_id != null` and `desc_id != null`
            - ...
        - else
          - `next_id == null` and `desc_id == null`
            - ...
          - `next_id != null` and `desc_id == null`
            - ...
          - `next_id == null` and `desc_id != null`
            - ...
          - `next_id != null` and `desc_id != null`
            - ...
        - else if exists `data_memo.desc_id = item.id` replace with next or desc
      - 1. `memo.desc_id = item.id`
        - if exists replace with next or desc
        - else delete `data_memo.desc_id` (memo entrypoint)
      - 2. `item.next_id` | `item.desc_id`
        - if exists replace with next | desc
    - `data_memo.node_id FK node.id` ON DELETE CASCADE
    - delete `item.node_id`
     
  - Polymorphic `node`: Flexible entity model whereby `data_*` are proxied by `node` and discriminated on type
  - `data` can be read, allows lazy rendering and unification of metadata of variadic data types: 
    - Strictly enforce equal permissions for `data_*` and `node`
      - Allows direct `data_*` access under node permissions
  - `node` owns the lifecycle of `data_*`
    - 1. Reverse ownership: `data_*.node_id` FK to `node.id`
      - Allows `get_data(node.id)` to fetch data with type check eg not knowning the `data_*.id` | `data_*.type` a priori
    - 2. Prohibit `data_*.create(...)` and `data_*.delete(...)`
    - 3. User provided with 2 delete mechanisms
      - A: Local - `item` or `link` deletion (eg remove this connection)
      - B: Global - `node` deletion (eg remove all connections and data)
    - Enabled by reverse ownership (data.node_id FK node.id) 
  - `node` holds the authoritative permissions for `item` and `data_*`
    - Allow tree traversal under ACL, eg user has permissions for `data_memo` but not for an `item` in that treelet
- **Directional Semantic and Hierarchical Connections**: 
  - `link` for semantic relationships (unidirectional)
  - `item` for hierarchical relationships (desc: ascendant->descendent, next: branch item->branch item)
- **Wild Nodes Can Exist**: `node` cannot exist without `item`
  - Creation: do not add contraints to the creation of nodes without items
  - Assimilation: **item.node_id 1:n node**, so an item can always reference a node
  - Deletion: cascading delete only if no `item.node_id` degeneracy
- **Multiple Semantic Relationships Between The Same Nodes**: 
  - (`src_id`, `dst_id`, `user_id`) is not unique
- **Treelet Composition**: Treelets (hierarchy of items) can be contained within other treelets eg for shared folders, document embedding, etc.
  - `data_memo` is the container for treelets
  - A Memo Proxy is an item whose `node[memo]`, used to mount a memo's treelet into another tree
    - `data_memo` becomes an indirection table for treelets, `item` proxies `data_memo`
    - Memo Proxy Pattern: `item` -> `node[?]` -[is memo]> `data_memo` -> `item` -> ...
  - **Treelet Cycles Allowed Under Constraints**: 
    - Cycles are allowed in the graph structure
    - Customer recursive queries prevent any loops via path tracking, returning a sentinel on cycle detection
- **Invalid references cannot exist**: Referential Integrity
  - Foreign keys prevent dangling references
  - CASCADE DELETE ensures no orphaned `node`
  - `node` table owns the lifecycle of `data_*`
- **All Treelets Traversable From Entrypoint**:
  - Entry flow: `user.memo_id` -> `data_memo` (user entrypoint) -> `item` (memo entrypoint) -> `item` ... (treelet)
  - Creation of a memo is the creation of a `node[memo]`
  - Recursive traversal via `desc_id` and `next_id` pointers
- **Treelets are Chunkable**:
  - `item` table supports chunking with custom query patterns including windows on next and desc pointers
- **Nodes and Tiles Can Appear in Many Treelets**:
  - `item.tile_id 1:n tile`: nb, this will be less used but worth noting
  - `item.node_id 1:n node`

## Schema

- `node`: id, type
  - type: NodeType (ENUM: text, file, memo, ...)
- `node_access`: id, node_id, user_id, permission
  - Index: `(user_id, node_id)`
  - Unique: `(node_id, user_id)` - prevent duplicate permissions
- `link_access`: id, link_id, user_id, permission: PermissionType
  - Index: `(user_id, link_id)`
  - Unique: `(link_id, user_id)` - prevent duplicate permissions
- `data_*`: id, node_id, ... (type-specific fields)
  - **data_*.node_id 1:n node**
  - Index: `(node_id)`
- `user`: id, user_id (unique), memo_id (unique)
  - **user.memo_id 1:1 data_memo**
- `data_memo`: id, node_id, desc_id
  - **data_memo.desc_id 1:n item** (entrypoint to treelet)
- `link`: id, src_id, dst_id
  - Indexes: `(src_id, dst_id)`, `(dst_id)`
  - **link.src_id 1:n node**
  - **link.dst_id 1:n node**
- `item`: id, node_id, desc_id (nullable), next_id (nullable), tile_id
  - Index: `(desc_id)`
  - Index: `(next_id)`
  - **item.node_id 1:n node**
  - **item.tile_id 1:n tile**
  - **item.desc_id 1:1 item**
- `tile`: id, x, y, w, h, viewbox_x, viewbox_y, viewbox_zoom


## Implementation Requirements

### Performance Settings

- Statement timeout: 5s
- Work memory: 256MB for recursive queries
- Query depth limit: 20
- Children per node limit: 1000

## Query Patterns

### Tree Traversal (Paginated)

Recursive CTE starting from memo's desc_id:
- Follow desc_id pointers depth-first
- Apply depth limit of 20
- Expected: <50ms for 10K nodes

### Get Thread O(1)

Direct lookup: SELECT from data_memo by id
- Expected: <1ms


## Memo Indirection Mechanism

### Problems Without Memos

1. **No tree composition**: Without memos, same node can't appear in multiple tree positions
2. **O(n) thread retrieval**: Recursive queries required

### Solution: Proxy Pattern

Memos enable treelet composition through indirection:

```
item -> node -> data_memo -> item (entrypoint) -> treelet
```

### Operations

#### add_treelet(memo_id)

1. Create new item with node_id = memo.node_id
2. This item becomes irrevocable entrypoint to treelet
3. Enables safe treelet inclusion in other treelets
4. Allows sharing treelet without parent access

#### Standard Item Operations

- Move treelet: Update item's desc_id/next_id (O(1))
- Copy treelet: Deep clone via memo mounting
- Delete treelet: Delete memo's item entry

### User Entry Point

Every user has a root memo (workspace):
- Created automatically via trigger on data_user insert
- Non-nullable memo_id in data_user enforces constraint
- Provides consistent entry to user's treelet graph

```
Pseudocode: On data_user insert
  IF memo_id IS NULL:
    Create node (type='memo')
    Create data_memo entry
    Set user.memo_id = new memo node
```

## Excluded Architectures

See `architecture.development.md` for discussion of excluded architectures including:
- Memo-Enforced (Architecture I)
- Pure Tree (III)
- Hybrid (IV) 
- Graph-Primary (V)
- Materialized Paths

## Additional Implementation Requirements


### 1. Node-Data Integrity

Enforced by reverse ownership pattern:
- Foreign keys with CASCADE DELETE on all data_* tables
- Triggers prevent direct INSERT/DELETE on data tables
- Node operations are the only way to manipulate data
- Ensure node.type matches data table type
- Validate one-to-one relationship (node appears in exactly one data table)

### 2. Data_memo Rendering

Special handling for data_memo as a data table:
- Renders by unfolding its desc_id tree
- Acts as container/proxy for treelets
- Business logic traverses from data_memo.desc_id
- Enables treelet composition without violating item uniqueness


### 3. Item Insert Optimization & Consistency

Database-enforced pointer consistency for O(1) insertion:

```
Pseudocode: On item insert
  IF inserting between items (has next_id):
    Find item where next_id = NEW.next_id
    Update that item's next_id = NEW.node_id
  
  Validate node exists before insert
```

### 4. Node Type Constraints

```sql
CREATE TYPE nodetype AS ENUM (
  'text', 'file', 'user', 'memo'
);
```

Type validation:
- Ensure node.type matches data table
- One-to-one relationship enforcement
- Type-specific constraints per data table


## Database Configuration

### Connection Pooling

- Max connections: 50 (Supabase limit)
- Idle timeout: 30s
- Connection timeout: 5s
- Statement timeout: 5s per query
- Idle transaction timeout: 10s

### Row Level Security (RLS) & Access Control

Node is the authoritative source for all permissions:

#### Permission Tables

1. **node_access**: Controls data access
   - Determines who can read/write node data
   - RLS policies enforce at query time
   - Permissions: view, edit, admin

2. **link_access**: Controls relationship visibility
   - User-specific link creation/sharing
   - Determines which relationships are visible
   - Enables private links in shared spaces

#### Key Features

1. **Treelet traversal under ACL**: Can navigate tree structure even when some nodes are restricted
2. **Dual-level control**: Via memo nodes AND individual item nodes
3. **Permission inheritance**: Creator permissions propagate through operations
4. **Granular sharing**: Share individual items within private treelets

#### Access Patterns

- Node access checked via node_access table join
- Link visibility filtered by link_access entries
- Recursive tree traversal continues even without direct node access
- Enables partial visibility within treelets

#### Design Benefits

- **Memo-level sharing**: Grant access to entire treelet via memo node
- **Item-level precision**: Override with specific item permissions
- **Link privacy**: User-specific relationship graphs
- **Traversal flexibility**: Structure visible even with data restrictions

### Transaction Boundaries

- ACID compliance for all operations
- Live UI queries for conflict resolution
- Atomic treelet operations via memo indirection

## Failure Modes

This section documents impossible states by design and actual failure scenarios.

### Impossible by Design

These errors cannot occur due to structural constraints:

1. **Orphaned data**: CASCADE DELETE prevents data without nodes
2. **Dangling references**: Foreign keys prevent invalid pointers
3. **Missing user workspace**: Trigger ensures every user has memo
4. **Inconsistent item pointers**: Triggers maintain linked list integrity
5. **Invalid node types**: ENUM constraint prevents undefined types

### Actual Failure Modes

Valid failures that must be handled:

1. **Constraint violations**: Duplicate keys, null violations
   - Client receives standard PostgreSQL error
   - No corruption possible

2. **Transaction conflicts**: Concurrent updates to same item
   - Last-write-wins with live query updates
   - No data loss, just overwrites

3. **Resource exhaustion**: Query depth/memory limits
   - Queries terminate cleanly
   - Path tracking prevents infinite loops

### Design Philosophy

Make invalid states unrepresentable rather than handling them at runtime. The database schema IS the business logic for structural invariants.

## Performance Validation

### Expected Performance Characteristics

These are estimates to be validated post-implementation:

- **O(1) thread retrieval**: Direct lookup via data_memo (~1ms expected)
- **Tree traversal**: <50ms for 10K nodes with proper indexes
- **Auth checks**: <5ms for 1M nodes (node table only, no joins)

### Benchmarking Plan

Post-deployment validation:
1. Generate representative test data (1M nodes, 100K items, 10K memos)
2. Measure query performance under concurrent load
3. Identify bottlenecks via EXPLAIN ANALYZE
4. Optimize based on actual usage patterns

## Operational Procedures

### Backup and Restore Strategy

**Status: Work in Progress**

Detailed backup procedures will be developed based on production usage patterns and actual failure scenarios.

### Migration Procedures

Schema changes follow these principles:
- All changes via versioned migration files
- Backwards-compatible changes preferred (ADD COLUMN, new tables)
- Breaking changes require coordinated deployment with application
- Use `IF NOT EXISTS` patterns for idempotent migrations
- Test migrations on copy of production data before deployment

### Performance Monitoring

Based on architecture, monitor:
- Recursive query depth and execution time
- Memory usage patterns for tree traversals
- Lock contention on high-traffic nodes
- Trigger execution time (especially user memo creation)
- Index hit rates and sequential scan occurrences

### Capacity Planning

**Status: Work in Progress**

Guidelines will be established after initial performance benchmarking.

### Disaster Recovery

**Status: Work in Progress**

Recovery procedures will be defined based on chosen backup strategy and RPO/RTO requirements.

## Future Optimizations

When scale demands (>10M nodes):
- Redis cache for hot paths
- Materialized path cache column
- Read replicas for tree queries
- Partitioning by workspace/user

## Later

- **Soft Delete**: Audit trails and undo functionality
- **Node Creation Mechanism**: Enforce nodes can only be created with corresponding data entry
- **Item Pointer Consistency**: Refine trigger logic for maintaining linked list integrity during concurrent operations