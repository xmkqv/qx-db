# Permission Inheritance Problem Statement

## Terms

- **Node**: Universal entity with data (via data_* tables) and permissions (via node_access)
- **Item**: Tree structure element that references a node and provides hierarchy via ascn_id
- **Explicit Permission**: Permission record in `node_access` table for a specific node
- **Inherited Permission**: Permission derived from an ancestor node via item's `ascn_id` chain
- **Permission Path**: Chain of items traversed to find permissions on their associated nodes
- **Permission Source**: The node where explicit permissions are found
- **Sparse Permission**: Only storing permissions on nodes when they differ from ancestor

## Current State

Every node requires explicit permission entries in `node_access` table. For a document with 100 nodes shared among 8 users, this creates 800 permission records.

## Core Problem

Permission explosion: O(nodes × users) records for granular access control.

## Proposed Solution: Context-Based Inheritance

Since clients access nodes through items, permission checks traverse: item → node → node_access. When no explicit permissions exist on a node, the check walks up the item's `ascn_id` chain to find ancestor nodes with permissions.

## Invariants

### I1: Permission Resolution
Every item must have resolvable permissions for its node, either through explicit assignment in `node_access` or via the item's ascendant chain reaching a root with explicit permissions.

### I2: Inheritance as Fallback
Permission check first examines the node directly; inherited permissions from ancestors are only consulted when no explicit permissions exist.

### I3: Root Authority
Nodes associated with root items (ascn_id = NULL) must have explicit permissions in `node_access` since they have no ancestor to inherit from.

## Maxims

### P1: Ascendant Inheritance (from I1)
Node permissions flow down the item tree via `ascn_id` chain - descendants inherit from ancestor nodes.

### P2: Direct First, Then Traverse (from I2)
Permission check starts at the target node, then traverses up the item chain, stopping at the first node with explicit permissions.

### P3: Sparse Storage (from I1, I2)
Only store permissions in `node_access` when a node's permissions differ from what would be inherited from its ancestors.

## Inheritance Model

```
Root Item (ascn_id=NULL) → Node R (explicit permissions required)
├── Item A → Node A (no explicit permissions, inherits from Node R)
│   └── Item A1 → Node A1 (inherits from Node A or Node R)
└── Item B → Node B (explicit permissions in node_access)
    └── Item B1 → Node B1 (inherits from Node B, not Node R)

Another Root Item (ascn_id=NULL) → Node R2 (explicit permissions required)
└── Item C → Node C (inherits from Node R2)
```

**Design Question**: Should the system enforce a single ultimate root item? Or allow multiple root items per user?
- **Multiple Roots**: More flexible, allows independent trees
- **Single Root**: Cleaner hierarchy, single entry point per user
- **Current Design**: Allows multiple roots (any item with ascn_id=NULL is a root)

## Access Path

Clients access content through items, not nodes directly:
```
Client → Item → Node → Data (via data_*)
                 ↓
              Permissions (via node_access)
```

## Permission Resolution Algorithm

```sql
CHECK_PERMISSION(item_id, user_id, required_bits):
  1. Get node_id from item
  2. Check node_access for this node_id
  3. If permissions found, return result
  4. Walk up item tree via ascn_id chain:
     a. Get parent item via ascn_id
     b. Check node_access for parent's node_id
     c. If permissions found, return result
     d. Continue up the chain
  5. Return FALSE if no permissions found

-- Alternative entry point when only node_id is known:
CHECK_PERMISSION_BY_NODE(node_id, user_id, required_bits):
  1. Check node_access directly for node_id
  2. If found, return result
  3. Find item(s) that reference this node
  4. For each item, check permission via item chain
  5. Return TRUE if any path grants access
```

## Edge Cases

### Links
- **Issue**: Nodes can be referenced by multiple paths (item tree + link connections)
- **Core Principle**: Links are references, not ownership - they grant limited, atomic access

#### Link Permission Model
Links provide atomic, non-cascading permissions limited to view/edit operations:

1. **Restricted Permissions**: Links can only grant view (4) or edit (2) permissions, never admin (1)
   - Rationale: Admin implies ownership/lifecycle control, inappropriate for references
   - Links are "shortcuts" or "citations", not ownership transfers

2. **Atomic Access**: Link permissions apply only to the destination node, not its descendants
   - No inheritance through links - permission doesn't flow to child items
   - Each link grants access to exactly one node

3. **Permission Calculation**: 
   ```sql
   -- Maximum permission via link = MIN(source_permission & 6, link_mode)
   -- Where 6 = view(4) + edit(2), excluding admin(1)
   ```

#### Implementation Options

**Option 1: Link Mode Field** (Recommended)
```sql
ALTER TABLE link ADD COLUMN permission_mode INTEGER DEFAULT 0;
-- 0 = no permission transfer
-- 4 = view only
-- 6 = view + edit (max)

-- Link permission check
IF link.permission_mode > 0 THEN
  user_link_permission = MIN(
    (source_node_permission & 6),  -- Strip admin from source
    link.permission_mode           -- Link's max permission
  )
END IF
```

**Option 2: Implicit View-Only**
- All links grant view permission if user can view source
- Simple but inflexible

**Option 3: Link Access Table**
```sql
CREATE TABLE link_access (
  link_id INTEGER REFERENCES link(id),
  user_id UUID,
  permission_bits INTEGER CHECK (permission_bits IN (0, 4, 6))
);
```
- Most flexible but adds complexity

#### Security Considerations

1. **No Permission Escalation**: Links cannot grant more permission than user has on source
2. **No Admin Propagation**: Administrative control never transfers through links
3. **Explicit Boundaries**: Link permissions are explicit and visible
4. **Audit Trail**: Link creation/permission can be logged

#### Use Cases

1. **Shared References**: User A shares read-only reference to their document with User B
2. **Collaborative Editing**: Grant edit access to specific nodes without tree ownership
3. **Cross-Tree Citations**: Reference nodes from other trees without importing
4. **Temporary Access**: Links can be deleted without affecting node ownership

### Flux Items
- **Issue**: Items with dual lineage (descendant.ascn_id ≠ stem.id) create dual permission paths
- **Solution**: Node requires permission through BOTH the item's ascendant chain AND stem chain
- **Implementation**: Check permissions on nodes via both item lineages
- **Result**: Least permissive wins - both paths must grant access to the node

### Orphaned Nodes
- **Issue**: Node exists without associated item, has no inheritance path
- **Solution**: Check `node_access` directly without inheritance

### Circular References
- **Issue**: Cycles in ascn_id chain (prevented by architecture)
- **Solution**: Depth limit (20) prevents infinite loops

### Multiple Root Items
- **Issue**: Users may have multiple disconnected trees (multiple roots)
- **Solution**: Each root requires explicit permissions
- **Consideration**: Should users have a primary root? Or allow multiple independent trees?
- **Current**: System allows multiple root items per user

### Same Node, Multiple Items
- **Issue**: A single node can be referenced by multiple items with different permission paths
- **Solution**: Permission check uses the item context (which item path was traversed)
- **Example**: Node N referenced by Item A (in Alice's tree) and Item B (in Bob's tree)
  - Via Item A: Inherits Alice's tree permissions
  - Via Item B: Inherits Bob's tree permissions
- **Implementation**: Permission check starts from specific item, not just node

## Performance Characteristics

### Expected Performance
- Item lookup from node: O(1) with unique index
- Ascendant traversal: O(depth), ~2ms/level
- Permission check on node: O(1) with index
- Typical depth: < 10 levels
- Total latency: < 20ms worst case
- With caching: < 5ms typical

### Optimization Strategies
1. Unique index on `item.node_id` for fast node→item lookup
2. Index on `item.ascn_id` for efficient tree traversal
3. Index on `node_access(node_id, user_id)` for fast permission checks
4. Optional: Cache effective permissions for frequently accessed nodes
5. Depth limit (20) prevents runaway queries

## Implementation Impact

### Storage Reduction
- Before: 100 nodes × 8 users = 800 records in `node_access`
- After: ~8 records (permissions on root node only)
- Reduction: 99% in typical hierarchical documents

### Management Simplification
- Set permissions on any node in the tree
- Descendant nodes automatically inherit via item relationships
- Override permissions on specific nodes when needed

### Migration Path
1. Deploy new permission check functions
2. Update RLS policies to use inheritance-aware functions
3. Stop creating redundant `node_access` records
4. Optional: Remove redundant permissions where node matches ancestor

## Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| Storage | 99% reduction | - |
| Performance | O(1) → O(depth) | +15ms worst case |
| Management | Hierarchical control | Complex debugging |
| Flexibility | Override anywhere | Dual logic paths |
| Security | Maintains boundaries | Flux complexity |

## Conclusion

Permission inheritance through the item tree structure allows nodes to inherit permissions from ancestor nodes via the `ascn_id` chain. This provides massive storage reduction in `node_access` and natural hierarchical control at the cost of slightly increased query complexity. The trade-off strongly favors implementation given typical tree depths and modern database performance.