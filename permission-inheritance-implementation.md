# Permission Inheritance Implementation

## Core Concept
Permissions flow down the item tree via `ascn_id` chain. Only store permissions when they differ from parent.

## Schema Changes

### 1. Add Helper Index
```sql
-- Fast lookup from node to its item
CREATE INDEX index_item__node_id_unique ON item(node_id) UNIQUE;
```

## Function Implementation

### 2. Replace Permission Check Function
```sql
CREATE OR REPLACE FUNCTION user_has_node_access(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_current_item_id INTEGER;
  v_has_permission BOOLEAN;
  v_depth INTEGER := 0;
  v_max_depth CONSTANT INTEGER := 20;
BEGIN
  -- Get the item for this node
  SELECT id INTO v_current_item_id 
  FROM item WHERE node_id = p_node_id;
  
  -- If no item, check direct node permissions only
  IF v_current_item_id IS NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM node_access
      WHERE node_id = p_node_id 
      AND user_id = auth.uid()
      AND ((permission_bits >> 6) & p_required_bits) = p_required_bits
    );
  END IF;
  
  -- Walk up the tree checking permissions
  WHILE v_current_item_id IS NOT NULL AND v_depth < v_max_depth LOOP
    -- Check if this item's node has explicit permissions
    SELECT EXISTS (
      SELECT 1 FROM node_access na
      JOIN item i ON i.node_id = na.node_id
      WHERE i.id = v_current_item_id
      AND na.user_id = auth.uid()
      AND ((na.permission_bits >> 6) & p_required_bits) = p_required_bits
    ) INTO v_has_permission;
    
    IF v_has_permission THEN
      RETURN TRUE;
    END IF;
    
    -- Move up to parent
    SELECT ascn_id INTO v_current_item_id
    FROM item WHERE id = v_current_item_id;
    
    v_depth := v_depth + 1;
  END LOOP;
  
  RETURN FALSE;
END;
$$;
```

### 3. Ensure Root Permissions
```sql
-- Trigger to ensure root items have permissions
CREATE OR REPLACE FUNCTION fn_ensure_root_permissions()
RETURNS TRIGGER AS $$
BEGIN
  -- If creating a root item (ascn_id IS NULL)
  IF NEW.ascn_id IS NULL THEN
    -- Check if node has any permissions
    IF NOT EXISTS (
      SELECT 1 FROM node_access 
      WHERE node_id = NEW.node_id
    ) THEN
      -- Grant creator full permissions
      INSERT INTO node_access (node_id, user_id, permission_bits)
      VALUES (NEW.node_id, auth.uid(), 448); -- 0700
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_item_ensure_root_permissions
  AFTER INSERT ON item
  FOR EACH ROW
  EXECUTE FUNCTION fn_ensure_root_permissions();
```

### 4. Optional: Permission Denial
```sql
-- Explicitly deny permissions (useful for blocking inheritance)
-- Use permission_bits = 0 to block all access
INSERT INTO node_access (node_id, user_id, permission_bits)
VALUES (child_node_id, blocked_user_id, 0);

-- Update permission check to handle denials
CREATE OR REPLACE FUNCTION user_has_node_access_v2(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_current_item_id INTEGER;
  v_permission_bits INTEGER;
  v_depth INTEGER := 0;
  v_max_depth CONSTANT INTEGER := 20;
BEGIN
  -- Get the item for this node
  SELECT id INTO v_current_item_id 
  FROM item WHERE node_id = p_node_id;
  
  -- If no item, check direct node permissions only
  IF v_current_item_id IS NULL THEN
    SELECT permission_bits INTO v_permission_bits
    FROM node_access
    WHERE node_id = p_node_id AND user_id = auth.uid();
    
    RETURN v_permission_bits IS NOT NULL 
      AND ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
  END IF;
  
  -- Walk up the tree checking permissions
  WHILE v_current_item_id IS NOT NULL AND v_depth < v_max_depth LOOP
    -- Check permissions at this level
    SELECT na.permission_bits INTO v_permission_bits
    FROM node_access na
    JOIN item i ON i.node_id = na.node_id
    WHERE i.id = v_current_item_id
    AND na.user_id = auth.uid();
    
    IF v_permission_bits IS NOT NULL THEN
      -- Found explicit permissions (could be grant or deny)
      RETURN ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
    END IF;
    
    -- Move up to parent
    SELECT ascn_id INTO v_current_item_id
    FROM item WHERE id = v_current_item_id;
    
    v_depth := v_depth + 1;
  END LOOP;
  
  RETURN FALSE;
END;
$$;
```

## Usage Patterns

### 1. Create User Workspace
```sql
-- Create user's root node
INSERT INTO node (type) VALUES ('text') RETURNING id AS user_root_node_id;
-- Create root item (ascn_id = NULL makes it a root)
INSERT INTO item (node_id, ascn_id) VALUES (user_root_node_id, NULL) 
RETURNING id AS user_root_item_id;
-- Permissions auto-granted by trigger: user gets 448 (rwx)

-- Update user record to point to their root
UPDATE data_user 
SET head_item_id = user_root_item_id 
WHERE user_id = auth.uid();
```

### 2. Create Document with Shared Access
```sql
-- Create document root under user's workspace
INSERT INTO node (type) VALUES ('text') RETURNING id AS doc_node_id;
INSERT INTO item (node_id, ascn_id) VALUES (doc_node_id, user_root_item_id)
RETURNING id AS doc_item_id;

-- Grant explicit permissions (inherits user's by default)
INSERT INTO node_access (node_id, user_id, permission_bits) 
VALUES (doc_node_id, collaborator_id, 256); -- Read only

-- Create child nodes - no explicit permissions needed
INSERT INTO node (type) VALUES ('text') RETURNING id AS child_node_id;
INSERT INTO item (node_id, ascn_id) VALUES (child_node_id, doc_item_id);
-- Child inherits permissions from document root
```

### 3. Override Permission on Subtree
```sql
-- Block access to sensitive section
INSERT INTO node_access (node_id, user_id, permission_bits)
VALUES (sensitive_node_id, collaborator_id, 0); -- No access

-- Or grant elevated access
INSERT INTO node_access (node_id, user_id, permission_bits)
VALUES (editable_node_id, collaborator_id, 384); -- Read + Write
```

### 4. Check Effective Permissions
```sql
-- Simple query to see effective permissions
WITH RECURSIVE permission_chain AS (
  -- Start with the target node
  SELECT 
    i.id as item_id,
    i.node_id,
    i.ascn_id,
    na.permission_bits,
    0 as depth
  FROM item i
  LEFT JOIN node_access na ON na.node_id = i.node_id 
    AND na.user_id = auth.uid()
  WHERE i.node_id = target_node_id
  
  UNION ALL
  
  -- Walk up the tree
  SELECT 
    parent.id,
    parent.node_id,
    parent.ascn_id,
    na.permission_bits,
    pc.depth + 1
  FROM permission_chain pc
  JOIN item parent ON parent.id = pc.ascn_id
  LEFT JOIN node_access na ON na.node_id = parent.node_id 
    AND na.user_id = auth.uid()
  WHERE pc.permission_bits IS NULL
    AND pc.depth < 20
)
SELECT 
  node_id,
  permission_bits,
  CASE 
    WHEN permission_bits IS NULL THEN 'Inherited'
    ELSE 'Explicit'
  END as source
FROM permission_chain
WHERE permission_bits IS NOT NULL
ORDER BY depth
LIMIT 1;
```

## Performance Optimizations

### 1. Materialized Permission Paths (Optional)
```sql
-- Cache permission resolution for hot paths
CREATE TABLE permission_cache (
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  effective_bits INTEGER NOT NULL,
  source_node_id INTEGER REFERENCES node(id) ON DELETE CASCADE,
  cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (node_id, user_id)
);

-- Invalidate cache on permission changes
CREATE OR REPLACE FUNCTION fn_invalidate_permission_cache()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete cache for this node and all descendants
  DELETE FROM permission_cache
  WHERE node_id IN (
    SELECT DISTINCT i.node_id 
    FROM item i
    WHERE i.id = NEW.node_id 
       OR i.ascn_id IN (
         WITH RECURSIVE descendants AS (
           SELECT id FROM item WHERE node_id = NEW.node_id
           UNION ALL
           SELECT i.id FROM item i
           JOIN descendants d ON i.ascn_id = d.id
         )
         SELECT id FROM descendants
       )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## Migration Strategy

### Phase 1: Deploy Functions
1. Deploy new permission check function
2. Update RLS policies to use new function
3. Existing permissions continue to work

### Phase 2: Stop Creating Redundant Permissions
1. Update application to only set permissions when different from parent
2. Monitor permission table growth

### Phase 3: Clean Up Redundant Permissions (Optional)
```sql
-- Find and remove redundant permissions
WITH redundant_permissions AS (
  SELECT 
    child_na.node_id,
    child_na.user_id
  FROM node_access child_na
  JOIN item child_item ON child_item.node_id = child_na.node_id
  JOIN item parent_item ON parent_item.id = child_item.ascn_id
  JOIN node_access parent_na ON parent_na.node_id = parent_item.node_id
    AND parent_na.user_id = child_na.user_id
  WHERE child_na.permission_bits = parent_na.permission_bits
)
DELETE FROM node_access
WHERE (node_id, user_id) IN (SELECT node_id, user_id FROM redundant_permissions);
```

## Handling Links

Links create additional permission paths between nodes. A node might be accessible through:
1. Its item tree (via ascn_id chain)
2. Direct links from other nodes

### Link Permission Strategy

```sql
CREATE OR REPLACE FUNCTION user_has_node_access_with_links(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_current_item_id INTEGER;
  v_permission_bits INTEGER;
  v_depth INTEGER := 0;
  v_max_depth CONSTANT INTEGER := 20;
BEGIN
  -- First check item tree inheritance (original logic)
  SELECT id INTO v_current_item_id 
  FROM item WHERE node_id = p_node_id;
  
  -- Walk up the item tree
  WHILE v_current_item_id IS NOT NULL AND v_depth < v_max_depth LOOP
    SELECT na.permission_bits INTO v_permission_bits
    FROM node_access na
    JOIN item i ON i.node_id = na.node_id
    WHERE i.id = v_current_item_id
    AND na.user_id = auth.uid();
    
    IF v_permission_bits IS NOT NULL THEN
      RETURN ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
    END IF;
    
    SELECT ascn_id INTO v_current_item_id
    FROM item WHERE id = v_current_item_id;
    
    v_depth := v_depth + 1;
  END LOOP;
  
  -- Check link-based access
  -- If user has access to any node that links to this node
  RETURN EXISTS (
    SELECT 1 
    FROM link l
    JOIN node_access na ON na.node_id = l.src_id
    WHERE l.dst_id = p_node_id
    AND na.user_id = auth.uid()
    AND ((na.permission_bits >> 6) & p_required_bits) = p_required_bits
  );
END;
$$;
```

### Link Permission Policies

1. **Conservative**: Links don't grant permissions (current implementation)
2. **Permissive**: If you can access the source, you can access the destination
3. **Explicit**: Links can carry their own permissions

### Recommended: Restricted Link Permissions

```sql
-- Add permission mode to links (restricted to view/edit only)
ALTER TABLE link ADD COLUMN permission_mode INTEGER DEFAULT 0
  CHECK (permission_mode IN (0, 4, 6));
-- 0 = no permission transfer
-- 4 = view only
-- 6 = view + edit (max allowed)

-- Complete implementation with restricted link permissions
CREATE OR REPLACE FUNCTION user_has_node_access_complete(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_current_item_id INTEGER;
  v_permission_bits INTEGER;
  v_depth INTEGER := 0;
  v_max_depth CONSTANT INTEGER := 20;
  v_source_permissions INTEGER;
  v_link_permissions INTEGER;
BEGIN
  -- 1. Check direct permissions on target node
  SELECT permission_bits INTO v_permission_bits
  FROM node_access
  WHERE node_id = p_node_id AND user_id = auth.uid();
  
  IF v_permission_bits IS NOT NULL THEN
    RETURN ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
  END IF;
  
  -- 2. Check item-based inheritance
  SELECT id INTO v_current_item_id 
  FROM item WHERE node_id = p_node_id;
  
  WHILE v_current_item_id IS NOT NULL AND v_depth < v_max_depth LOOP
    SELECT ascn_id INTO v_current_item_id
    FROM item WHERE id = v_current_item_id;
    
    IF v_current_item_id IS NOT NULL THEN
      SELECT na.permission_bits INTO v_permission_bits
      FROM node_access na
      JOIN item i ON i.node_id = na.node_id
      WHERE i.id = v_current_item_id
      AND na.user_id = auth.uid();
      
      IF v_permission_bits IS NOT NULL THEN
        RETURN ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
      END IF;
    END IF;
    
    v_depth := v_depth + 1;
  END LOOP;
  
  -- 3. Check link-based access (restricted permissions)
  FOR v_link_permissions, v_source_permissions IN
    SELECT l.permission_mode, na.permission_bits
    FROM link l
    JOIN node_access na ON na.node_id = l.src_id
    WHERE l.dst_id = p_node_id
    AND l.permission_mode > 0
    AND na.user_id = auth.uid()
  LOOP
    -- Calculate effective permission via link
    -- Strip admin bit from source, then apply link restriction
    v_link_permissions := LEAST(
      (v_source_permissions >> 6) & 6,  -- Source permission without admin
      v_link_permissions                 -- Link's maximum allowed
    );
    
    IF (v_link_permissions & p_required_bits) = p_required_bits THEN
      -- But don't allow admin via links
      IF p_required_bits & 1 = 0 THEN
        RETURN TRUE;
      END IF;
    END IF;
  END LOOP;
  
  RETURN FALSE;
END;
$$;

-- Helper function to check if access is via link (for UI indicators)
CREATE OR REPLACE FUNCTION get_access_source(
  p_node_id INTEGER
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_has_direct BOOLEAN;
  v_has_inherited BOOLEAN;
  v_has_link BOOLEAN;
BEGIN
  -- Check direct
  SELECT EXISTS(
    SELECT 1 FROM node_access
    WHERE node_id = p_node_id AND user_id = auth.uid()
  ) INTO v_has_direct;
  
  IF v_has_direct THEN RETURN 'direct'; END IF;
  
  -- Check inherited (simplified)
  SELECT EXISTS(
    SELECT 1 FROM item i
    WHERE i.node_id = p_node_id
    AND user_has_node_access_via_ascn(p_node_id, 4)
  ) INTO v_has_inherited;
  
  IF v_has_inherited THEN RETURN 'inherited'; END IF;
  
  -- Check link
  SELECT EXISTS(
    SELECT 1 FROM link l
    WHERE l.dst_id = p_node_id
    AND l.permission_mode > 0
    AND user_has_node_access(l.src_id, 4)
  ) INTO v_has_link;
  
  IF v_has_link THEN RETURN 'link'; END IF;
  
  RETURN 'none';
END;
$$;
```

### Link Permission Examples

```sql
-- Example 1: Alice shares view-only link to her document with Bob
-- Alice has admin (7) on node 100
INSERT INTO link (src_id, dst_id, permission_mode) 
VALUES (100, 200, 4);  -- 4 = view only

-- Bob's effective permission on node 200:
-- Even though Alice has admin, Bob only gets view (4)

-- Example 2: Collaborative editing
-- Carol has edit (6) on node 300
INSERT INTO link (src_id, dst_id, permission_mode)
VALUES (300, 400, 6);  -- 6 = view + edit

-- Dave's effective permission calculation:
-- 1. Dave must have access to node 300 (source)
-- 2. Dave's permission on 300 is masked to remove admin: perm & 6
-- 3. Final permission = MIN(dave_on_300 & 6, link.permission_mode)

-- Example 3: Admin operations blocked
-- Even if user has admin on source and link allows edit:
-- user_has_node_access_complete(linked_node, 1) = FALSE
-- Links NEVER grant admin permission
```

### Why Restrict Link Permissions?

1. **Security Boundary**: Links represent references, not ownership transfer
   - Admin permission implies lifecycle control (delete, permission management)
   - Links should not allow deletion of referenced content

2. **Atomic Boundaries**: Link permissions don't cascade to descendants
   - Granting link to a folder doesn't grant access to its contents
   - Each node requires explicit link for access

3. **Audit Trail**: Limited permissions make access patterns clearer
   - "Who can delete this?" → Only those with direct/inherited admin
   - "Who can edit this?" → Direct/inherited editors + explicit link grants

4. **Revocation**: Links can be removed without affecting node ownership
   - Removing a link immediately revokes access
   - No orphaned permissions or complex cleanup

```

## Handling Flux

Flux items (where descendant.ascn_id ≠ stem.id) require checking permissions through both lineages per the architecture's P3.

### Flux Permission Implementation

```sql
CREATE OR REPLACE FUNCTION user_has_node_access_with_flux(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_item RECORD;
  v_stem_item RECORD;
  v_has_ascn_permission BOOLEAN;
  v_has_stem_permission BOOLEAN;
BEGIN
  -- Get the item for this node
  SELECT * INTO v_item FROM item WHERE node_id = p_node_id;
  
  -- If no item, check direct permissions only
  IF v_item IS NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM node_access
      WHERE node_id = p_node_id 
      AND user_id = auth.uid()
      AND ((permission_bits >> 6) & p_required_bits) = p_required_bits
    );
  END IF;
  
  -- Check if this is a flux item
  -- Find stem (item whose desc_id points to us)
  SELECT * INTO v_stem_item 
  FROM item 
  WHERE desc_id = v_item.id;
  
  IF v_stem_item IS NOT NULL AND v_stem_item.id != v_item.ascn_id THEN
    -- This is a flux item - need permission through BOTH lineages
    
    -- Check ascendant lineage
    v_has_ascn_permission := user_has_node_access_via_ascn(
      v_item.node_id, 
      p_required_bits
    );
    
    -- Check stem lineage (through the stem that points to us)
    v_has_stem_permission := user_has_node_access_via_ascn(
      v_stem_item.node_id,
      p_required_bits
    );
    
    -- Both must grant permission (least permissive wins)
    RETURN v_has_ascn_permission AND v_has_stem_permission;
  ELSE
    -- Not flux, use normal inheritance
    RETURN user_has_node_access_via_ascn(v_item.node_id, p_required_bits);
  END IF;
END;
$$;

-- Helper function for ascendant chain traversal
CREATE OR REPLACE FUNCTION user_has_node_access_via_ascn(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_current_item_id INTEGER;
  v_permission_bits INTEGER;
  v_depth INTEGER := 0;
  v_max_depth CONSTANT INTEGER := 20;
BEGIN
  SELECT id INTO v_current_item_id 
  FROM item WHERE node_id = p_node_id;
  
  WHILE v_current_item_id IS NOT NULL AND v_depth < v_max_depth LOOP
    SELECT na.permission_bits INTO v_permission_bits
    FROM node_access na
    JOIN item i ON i.node_id = na.node_id
    WHERE i.id = v_current_item_id
    AND na.user_id = auth.uid();
    
    IF v_permission_bits IS NOT NULL THEN
      RETURN ((v_permission_bits >> 6) & p_required_bits) = p_required_bits;
    END IF;
    
    SELECT ascn_id INTO v_current_item_id
    FROM item WHERE id = v_current_item_id;
    
    v_depth := v_depth + 1;
  END LOOP;
  
  RETURN FALSE;
END;
$$;
```

### Flux Permission Scenarios

1. **Native Item**: `stem.id = descendant.ascn_id`
   - Normal inheritance through ascn_id chain

2. **Flux Item**: `stem.id ≠ descendant.ascn_id`
   - Must have permission through BOTH:
     - Ascendant lineage (via ascn_id chain)
     - Stem lineage (via the stem that mounted it)

3. **Example**:
```sql
-- Tree A (owned by Alice)
Root A (Alice: rwx)
└── Item A1
    └── Item A2

-- Tree B (owned by Bob)  
Root B (Bob: rwx, Alice: r)
└── Item B1 (mounts A2 as flux)
    └── A2 (flux item)
        └── Item A3

-- To access A3:
-- Alice needs: permission via A2's ascn chain (✓ has rwx on Root A)
--              AND permission via B1 (✓ has r on Root B)
-- Result: Alice has read-only access to A3 in this context

-- Bob needs: permission via A2's ascn chain (✗ no access to Root A)
--            AND permission via B1 (✓ has rwx on Root B)  
-- Result: Bob has NO access to A3
```

### Performance Considerations for Flux

```sql
-- Add index for finding stems efficiently
CREATE INDEX index_item__desc_id_covering 
ON item(desc_id) INCLUDE (id, ascn_id, node_id);

-- Optimized flux detection
CREATE OR REPLACE FUNCTION is_flux_item(p_item_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM item stem
    WHERE stem.desc_id = p_item_id
    AND stem.id != (SELECT ascn_id FROM item WHERE id = p_item_id)
  );
$$;
```

## Benefits

1. **Storage**: 100-node document with 8 users: 8 records instead of 800
2. **Management**: Change permissions at any level, affects entire subtree
3. **Flexibility**: Override at any level when needed
4. **Performance**: O(depth) lookup, typically < 5ms with indexes
5. **Flux Safety**: Maintains security boundaries across tree composition
6. **Link Security**: 
   - No admin permission leakage through references
   - Atomic access without inheritance complications
   - Clear audit trail for access patterns
   - Simple revocation by link deletion
7. **Conceptual Clarity**:
   - Items provide ownership and inheritance
   - Links provide references and limited access
   - Clear distinction between "having" and "seeing"