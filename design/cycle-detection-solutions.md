# Memo Cycle Detection: Solution Analysis

## Problem Statement

Prevent circular memo mounting where memos form a cycle through any number of intermediate steps, creating an infinite loop.

### Examples of Cycles to Detect

1. **Direct cycle (Order 1)**: A → B → A
2. **Indirect cycle (Order 2)**: A → B → C → A  
3. **Deep cycle (Order N)**: A → B → C → D → E → F → A
4. **Multiple paths**: A → B → C and A → D → C (not a cycle, valid DAG)

The challenge is detecting cycles of arbitrary depth efficiently before they're created.

## Core Architecture Constraints

1. **Memo Indirection Pattern**: `item -> node(type=memo) -> data_memo -> item(entrypoint) -> treelet`
2. **Item Uniqueness**: Each item exists in exactly one physical location
3. **Items Never Move Between Memos**: Items are bound to their containing memo
4. **Separation of Concerns**: Node table handles structure, data tables handle content

## Pattern to Detect

```
Direct Cycle (A → B → A):
item → node(A) → data_memo → item → node(B) → data_memo → item → node(A)
                                                                     ↑
                                                                   CYCLE

Indirect Cycle (A → B → C → A):
item → node(A) → data_memo → item → node(B) → data_memo → item → node(C) → data_memo → item → node(A)
         ↑                                                                                          |
         |__________________________________________________________________________________________|
                                                    CYCLE
```

## Solution Candidates

### 1. O(n) Traversal (Accepted Baseline)

**Implementation**: Recursive CTE following memo chains to detect cycles of any depth
```sql
-- Check if mounting memo_A into location_B would create a cycle
-- Need to verify: Can we reach location_B from memo_A's descendants?
WITH RECURSIVE memo_descendants AS (
  -- Start with the memo we want to mount
  SELECT $memo_A as node_id, 0 as depth, ARRAY[$memo_A] as path
  
  UNION ALL
  
  -- Follow all memo mounts downward
  SELECT 
    i.node_id, 
    md.depth + 1,
    md.path || i.node_id
  FROM memo_descendants md
  JOIN data_memo dm ON dm.node_id = md.node_id
  JOIN item i ON i.desc_id = dm.desc_id  -- Items mounted in this memo
  JOIN node n ON n.id = i.node_id AND n.type = 'memo'  -- That are memos
  WHERE md.depth < 100
    AND NOT i.node_id = ANY(md.path)  -- Prevent infinite recursion
)
SELECT EXISTS(
  SELECT 1 FROM memo_descendants 
  WHERE node_id = $location_B
);
```

**Example Detection**:
- Mounting A into C when B→C→A exists:
  1. Start with A
  2. Find A's descendants: (none initially)
  3. After mount would include C's descendants
  4. C contains A (via B) = CYCLE DETECTED

**Pros**: 
- Pure, no schema changes
- Handles cycles of any depth
- Path tracking enables debugging

**Cons**:
- O(n) where n = total memos in subtree
- Performance degrades with deep/wide hierarchies
- Must run before every memo mount

### 2. Principal_id on Items (Sparse Field)

**Schema**: `item.principal_id` - points to the "true owner" memo

**Implementation**:
- Set principal_id = containing memo for regular items
- For memo proxy items, principal_id = the memo being proxied
- Cycle check: `SELECT 1 WHERE principal_id = $mounting_location`

**Pros**:
- O(1) cycle detection
- Clear ownership model

**Cons**:
- Sparse field (only useful for memo items)
- Requires careful maintenance on creation

### 3. Item_proxy Table

**Schema**: 
```sql
CREATE TABLE item_proxy (
  item_id UUID PRIMARY KEY REFERENCES item(node_id),
  proxied_memo_id UUID NOT NULL REFERENCES node(id),
  UNIQUE(proxied_memo_id)
);
```

**Implementation**:
- Entry only exists for items that proxy memos
- Cycle check: Join through proxy table

**Pros**:
- No sparse fields
- Clean separation of concerns
- Can add proxy-specific metadata

**Cons**:
- Additional join for memo operations
- Another table to maintain

### 4. Memo_ancestry Table

**Schema**:
```sql
CREATE TABLE memo_ancestry (
  descendant_id UUID REFERENCES node(id),
  ancestor_id UUID REFERENCES node(id),
  depth INT NOT NULL,
  PRIMARY KEY (descendant_id, ancestor_id)
);
```

**Implementation**:
- Materialized transitive closure
- Update on every memo mount/unmount
- Cycle check: `EXISTS(SELECT 1 WHERE descendant_id = $target AND ancestor_id = $mounting)`

**Pros**:
- O(1) for any ancestry query
- Enables "all memos containing X" queries

**Cons**:
- Maintenance complexity
- Storage overhead (n² worst case)
- Complex update logic

### 5. Node.memo_id (Everything is Fluxed)

**Schema**: Every node belongs to a memo/flux
```sql
ALTER TABLE node ADD COLUMN memo_id UUID REFERENCES node(id);
```

**Pros**:
- Universal containment model
- Fast "what memo contains this" queries

**Cons**:
- Breaks the polymorphic model
- Circular reference (memo nodes contain themselves?)
- Major architectural shift

### 6. Hybrid: Memo_mount Table

**Schema**:
```sql
CREATE TABLE memo_mount (
  parent_memo_id UUID NOT NULL,
  child_memo_id UUID NOT NULL,
  mount_item_id UUID NOT NULL REFERENCES item(node_id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (parent_memo_id, child_memo_id),
  CHECK (parent_memo_id != child_memo_id)
);

-- Prevent cycles with trigger using recursive CTE on this focused table
```

**Pros**:
- Explicit mount tracking
- Optimized for cycle detection
- Preserves existing architecture
- Can add mount-specific metadata

**Cons**:
- Denormalization (info derivable from items)
- Must be kept in sync

## Recommendation

**Short term**: Accept O(n) traversal with optimizations:
1. Add `item.is_memo_mount BOOLEAN GENERATED ALWAYS AS (node_id IN (SELECT node_id FROM node WHERE type = 'memo'))`
2. Partial index on memo mounts only
3. Limit depth to 20 (reasonable for UI)

**Medium term**: Implement memo_mount table:
- Explicit tracking of memo relationships
- Enables O(log n) cycle detection on smaller dataset
- Foundation for future mount-specific features

**Long term**: Consider if memo indirection is the right pattern vs. explicit mount objects

## Performance Analysis for Multi-Level Cycles

### Worst Case Scenarios

1. **Linear Chain**: A → B → C → D → E → F
   - O(n) traversal must check n nodes
   - With index: ~1ms per level, 6ms total
   - At depth 20: ~20ms

2. **Wide Tree**: A → {B₁, B₂, ..., B₁₀₀} → {C₁, C₂, ..., C₁₀₀₀}
   - O(n) where n = all descendants
   - Could be checking 1000+ nodes
   - Performance: 100-500ms

3. **Detection Timing**:
   - **Early cycles** (A → B → A): Fast, ~2ms
   - **Deep cycles** (A → ... → Z → A): Slow, ~50ms+
   - **No cycle**: Must traverse entire tree (worst case)

### Real-World Implications

For a typical document system:
- Average memo depth: 3-5 levels
- Average memos per level: 5-10
- Total nodes to check: 50-500
- Expected performance: 5-50ms

This suggests O(n) may be acceptable with proper limits.

## Decision Factors

1. **Query frequency**: How often are memos mounted vs. queried?
2. **Depth reality**: Will real hierarchies exceed 5-10 levels?
3. **Feature growth**: Will mounts need additional metadata?
4. **Consistency requirements**: Can we tolerate brief windows of inconsistency?
5. **Cycle probability**: How often do users attempt invalid mounts?

## Next Steps

1. Benchmark O(n) solution with realistic data
2. Prototype memo_mount table approach
3. Decide on acceptable performance thresholds
4. Consider UI/UX implications of depth limits