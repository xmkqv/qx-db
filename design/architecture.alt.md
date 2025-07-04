# qx-db Alternative Architecture: Path-Based Trees

## Executive Summary

This alternative eliminates the complex pointer-based tree structure in favor of materialized paths. Instead of `desc_id`/`next_id` pointers, each item stores its full path as a string. Tree composition is achieved through path prefixing rather than memo indirection.

**Key simplification**: Replace graph traversal with string operations.

## Core Invariants (Unchanged)

### I1: Universal Node Identity
Every entity is a node with unique identity, type, and timestamps.

### I2: Data-Node Bijection
Every node has exactly one data entry. Every data entry has exactly one node.

### I3: Referential Integrity  
All pointers must reference existing entities or be null.

### I4: Tree Traversability
Every tree must be traversable from a well-defined entrypoint.

### I5: Tree Composition
Same node can appear in multiple tree positions through path aliasing.

### I6: Lifecycle Authority
Nodes own the lifecycle of their data and connections.

## Design Principles

### P1: Path as Structure
- Tree structure encoded in path strings
- No pointer maintenance required
- Natural ordering via string comparison

### P2: Composition via Aliasing
- Alias items point to other paths
- Resolution happens at query time
- No complex memo indirection

### P3: Simplified Deletion
- Delete item = delete path
- Children found by path prefix
- No trigger complexity

## Schema

```
node: (unchanged)
  id: UUID PRIMARY KEY
  type: NodeType NOT NULL
  created_at, updated_at: TIMESTAMPTZ
  creator_id: UUID

item:
  id: UUID PRIMARY KEY
  node_id: UUID REFERENCES node(id) ON DELETE CASCADE
  path: TEXT NOT NULL  -- e.g., "/root/folder1/doc1"
  parent_path: TEXT    -- e.g., "/root/folder1"
  name: TEXT NOT NULL  -- e.g., "doc1"
  position: INTEGER    -- sort order among siblings
  is_alias: BOOLEAN DEFAULT FALSE
  alias_target: TEXT   -- if is_alias, points to another path
  UNIQUE(path)
  INDEX(parent_path, position)

-- Data tables remain unchanged
data_text, data_file, data_user, data_memo: (unchanged)

-- Simplified: no desc_id/next_id pointers
-- Simplified: no complex deletion triggers
```

## Operations

### Tree Traversal
```sql
-- Get children
SELECT * FROM item 
WHERE parent_path = '/root/folder1'
ORDER BY position;

-- Get descendants  
SELECT * FROM item
WHERE path LIKE '/root/folder1/%'
ORDER BY path;

-- Get ancestors
WITH RECURSIVE ancestors AS (
  SELECT parent_path 
  FROM item 
  WHERE path = '/root/folder1/doc1'
  
  UNION
  
  SELECT i.parent_path
  FROM ancestors a
  JOIN item i ON i.path = a.parent_path
  WHERE a.parent_path IS NOT NULL
)
SELECT * FROM ancestors;
```

### Tree Composition
```sql
-- Create an alias (mount point)
INSERT INTO item (node_id, path, parent_path, name, is_alias, alias_target)
VALUES (
  $memo_node_id,
  '/root/shared',
  '/root',
  'shared',
  TRUE,
  '/users/alice/documents'
);

-- Resolve aliases during traversal
CREATE FUNCTION resolve_path(item_path TEXT) RETURNS TEXT AS $$
  SELECT CASE 
    WHEN is_alias THEN alias_target
    ELSE item_path
  END
  FROM item
  WHERE path = item_path;
$$ LANGUAGE SQL;
```

### Deletion
```sql
-- Simple cascade: delete item and all descendants
DELETE FROM item 
WHERE path = '/root/folder1' 
   OR path LIKE '/root/folder1/%';

-- No complex pointer updates needed!
```

## Advantages

### 1. Simplicity
- **Eliminated**: desc_id, next_id, complex triggers
- **Reduced**: FK relationships, edge cases
- **Natural**: Path operations are intuitive

### 2. Performance  
- **Fast children lookup**: Single index seek on parent_path
- **Fast descendant lookup**: LIKE query with index
- **No recursion**: Path encodes full hierarchy

### 3. Maintainability
- **Self-documenting**: Paths show structure visually
- **Easy debugging**: Can see tree structure in raw data
- **Simple moves**: Just update path strings

### 4. Tree Composition
- **Cleaner**: Aliases are explicit, not hidden in memo indirection
- **Flexible**: Can alias to any path, not just memo roots
- **Transparent**: Clear when crossing tree boundaries

## Trade-offs

### Disadvantages
1. **Path length limits**: Very deep trees hit string limits
2. **Rename cost**: Moving parent requires updating all descendant paths
3. **Less flexible**: Harder to represent DAGs or complex graphs

### Mitigations
1. **Path compression**: Use IDs instead of names in paths
2. **Batch updates**: Efficient path rewriting operations
3. **Hybrid approach**: Add link table for non-tree relationships

## Migration Strategy

From current architecture:
1. Generate paths from desc_id/next_id traversal
2. Populate path, parent_path, position columns
3. Convert memos to aliases
4. Drop desc_id, next_id columns
5. Remove complex triggers

## Conclusion

This path-based approach trades flexibility for simplicity. By encoding tree structure in paths rather than pointers, we eliminate most of the complexity around tree maintenance, traversal, and composition. The result is a system that's easier to understand, debug, and maintain while still meeting all core invariants.

**Core insight**: Sometimes the best graph database is not a graph database.