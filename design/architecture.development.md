# qx-db Architecture

## Core Concepts

### Polymorphic Node System

Every entity is a node with a type. Data tables store type-specific fields while referencing the base node.

### Terminology

- **Node**: Base entity with id, type, timestamps
- **Item**: Tree container with uniqueness constraint on node_id
  - `desc_id`: Points to first child
  - `next_id`: Points to peer
  - `ascn_id`: Points to parent (proposed)
- **Link**: Directed edge between nodes
- **Memo**: Enables tree composition via indirection
  - Solves item uniqueness violation
  - Enables O(1) thread retrieval
- **Orphan**: Node without item (graph-native)


## System Principles

### 1. Referential Integrity

Foreign key violations = bugs. Handle:
- Orphan prevention
- Cascade deletion
- Cyclic mount detection
- Dangling reference prevention
- Access record consistency

### 2. Tree Composition

Required for:
- Shared folder mounting
- Document embedding
- Cross-workspace sharing

### 3. Node-Data Separation

- **Node table**: Structure index
- **Data tables**: Content storage
- **Benefits**:
  - Auth checks without content joins
  - Type-specific optimization
  - Clear API boundaries

## Tree Patterns

### Current: Bidirectional Pointers

```sql
-- Structure
data_memo.desc_id -> first item
item.desc_id -> first child
item.next_id -> next peer

-- Traversal: follow pointers depth-first
```

### Alternative: Parent Pointers

```sql
-- Structure
item.ascn_id -> parent
item.next_id -> peer order

-- Find children
SELECT * FROM item WHERE ascn_id = ?
```

**Recommendation**: Store both directions with triggers

## Schema

### Tables

- `node`: id, type, timestamps
- `node_access`: node_id, user_id, permission
- `data_*`: Type-specific content (node_id as PK/FK)
- `link`: src_id, dst_id
- `item`: node_id, desc_id, next_id
- `data_memo`: desc_id -> root item

## Architectures

### I: Memo-Enforced (Recommended)

Every node belongs to a memo.

```sql
-- Tree composition via memo mounting
INSERT INTO item (node_id) VALUES (memo_B_node_id);

-- Thread retrieval O(1)
SELECT * FROM data_memo WHERE id = $thread_id;
```

**Pros**:
- Simple mental model
- Clear boundaries
- Guaranteed composition

**Cons**:
- Everything needs memos
- Move/merge complexity

### II: Proxy-Hybrid

Memo mounts + graph-native nodes.

**Pros**:
- Maximum flexibility
- Supports pure graph data

**Cons**:
- Higher complexity
- Mixed storage modes


## Recommendation

**Architecture II** (Proxy-Hybrid) selected for maximum flexibility.

### Implementation Checklist

- [ ] Add `ascn_id` to items
- [ ] Index link endpoints
- [ ] Implement cycle detection
- [ ] Add query timeouts
- [ ] Set depth limits (20)
- [ ] Set child limits (1000)

## Why Memos

### Problems Without Memos

1. **No tree composition**: Item uniqueness prevents mounting
2. **O(n) thread retrieval**: Recursive queries required

### Solution

```sql
-- Memo provides indirection
INSERT INTO item (node_id) VALUES (memo_B_node_id);

-- O(1) thread access
SELECT * FROM data_memo WHERE id = $thread_id;
```

Memo = minimal solution for tree composition.


## Performance Notes

### Tree Traversal

```sql
-- Paginated tree query
WITH RECURSIVE tree AS (
  SELECT i.*, 1 as depth
  FROM data_memo dm
  JOIN item i ON i.id = dm.desc_id
  WHERE dm.id = $memo_id
  
  UNION ALL
  
  SELECT i.*, t.depth + 1
  FROM tree t
  JOIN item i ON i.id = t.desc_id
  WHERE t.depth < $max_depth
)
SELECT * FROM tree
LIMIT $limit OFFSET $offset;
```

### Optimization

- Cache memo trees in Redis
- Add breadcrumb paths for navigation
- Use SERIALIZABLE for critical ops
- Leverage PostgreSQL ACID guarantees

## Excluded Architectures

### III: Pure Tree
- **Fatal**: No tree composition (item uniqueness)
- Links are secondary

### IV: Hybrid
- **Fatal**: No tree composition
- **Fatal**: O(n) thread retrieval

### V: Graph-Primary
- Virtual trees from links
- **Fatal**: View staleness breaks RI
- **Fatal**: Poor traversal performance

### Pattern 1D: Materialized Paths
- **Fatal**: Path rewriting prevents mounting

# Later

## Soft Delete Strategy

Choice between tombstones vs hard deletes. Considerations:
- Audit trails
- Undo capability
- Storage growth
- Referential integrity with soft deletes

## Conflict Resolution

Simple "most recently changed wins" approach:
- `updated_at` timestamps determine winner
- No complex merge logic initially
- UI reactively updates from DB ground truth
- ACID transactions prevent corruption