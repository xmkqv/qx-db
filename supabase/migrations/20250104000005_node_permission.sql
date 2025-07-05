-- Migration: Access control tables and views

-- =============================================================================
-- ENUMS
-- =============================================================================

-- Permission type enum
CREATE TYPE PermissionType AS ENUM ('view', 'edit', 'admin');

-- =============================================================================
-- CUSTOM OPERATORS
-- =============================================================================

-- Function to compare permissions (returns true if left >= right)
CREATE OR REPLACE FUNCTION fn_permission_gte(left_perm PermissionType, right_perm PermissionType)
RETURNS BOOLEAN AS $$
  SELECT 
    CASE left_perm
      WHEN 'admin' THEN true
      WHEN 'edit' THEN right_perm IN ('view', 'edit')
      WHEN 'view' THEN right_perm = 'view'
    END;
$$ LANGUAGE sql IMMUTABLE;

-- Custom operator for permission comparison
CREATE OPERATOR >= (
  LEFTARG = PermissionType,
  RIGHTARG = PermissionType,
  FUNCTION = fn_permission_gte
);

-- =============================================================================
-- TABLE DEFINITIONS
-- =============================================================================

-- Node access table
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE ON UPDATE CASCADE,  -- External auth IDs can change
  permission PermissionType NOT NULL,
  UNIQUE(node_id, user_id)
);

-- Link permissions derived from src node - no separate table needed

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Indexes for node_access
CREATE INDEX index_node_access__node_id ON node_access(node_id);
CREATE INDEX index_node_access__user_id ON node_access(user_id);
CREATE INDEX index_node_access__user_id__permission ON node_access(user_id, permission);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- View for node permissions using array operations
CREATE VIEW node_permission AS
SELECT 
  node_id, 
  user_id,
  fn_util_highest_permission(array_agg(permission::text))::PermissionType as permission
FROM (
  -- Explicit grants
  SELECT node_id, user_id, permission 
  FROM node_access
  
  UNION ALL
  
  -- Creator always has admin access
  SELECT id as node_id, creator_id as user_id, 'admin'::PermissionType as permission
  FROM node 
  WHERE is_owned  -- Use generated column
) access_union
GROUP BY node_id, user_id;

-- Create an alias view for backward compatibility
CREATE VIEW accessible_nodes AS
SELECT * FROM node_permission;

-- Materialized view for user workspace roots (refreshed on user creation)
CREATE MATERIALIZED VIEW user_workspace_roots AS
SELECT 
  du.user_id,
  du.username,
  du.head_item_id,
  i.node_id as root_node_id,
  i.tile_id as root_tile_id
FROM data_user du
JOIN item i ON i.id = du.head_item_id
WHERE i.is_root;

CREATE INDEX index_user_workspace_roots__user_id ON user_workspace_roots(user_id);

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function for flux-aware permission checking
CREATE OR REPLACE FUNCTION fn_node_check_access_flux(
  p_node_id INTEGER,
  p_user_id UUID,
  p_required_permission PermissionType DEFAULT 'view'
) RETURNS BOOLEAN AS $$
DECLARE
  item_record RECORD;
  has_access BOOLEAN := FALSE;
  permission_rank INTEGER;
  required_rank INTEGER;
BEGIN
  -- Convert permissions to ranks for comparison
  required_rank := CASE p_required_permission
    WHEN 'view' THEN 1
    WHEN 'edit' THEN 2
    WHEN 'admin' THEN 3
  END;
  
  -- First check direct node access
  SELECT 
    CASE permission
      WHEN 'view' THEN 1
      WHEN 'edit' THEN 2
      WHEN 'admin' THEN 3
    END INTO permission_rank
  FROM node_permission
  WHERE node_id = p_node_id AND user_id = p_user_id;
  
  IF permission_rank >= required_rank THEN
    RETURN TRUE;
  END IF;
  
  -- If node is part of an item, check flux permissions
  FOR item_record IN 
    SELECT i.*, stem.id as stem_id
    FROM item i
    LEFT JOIN item stem ON stem.desc_id = i.id
    WHERE i.node_id = p_node_id
  LOOP
    -- If this is a flux item (ascn_id != stem_id), check both lineages
    IF item_record.stem_id IS NOT NULL AND item_record.ascn_id != item_record.stem_id THEN
      -- Must have access via BOTH lineages (least permissive wins)
      -- Check stem lineage
      SELECT 
        CASE permission
          WHEN 'view' THEN 1
          WHEN 'edit' THEN 2
          WHEN 'admin' THEN 3
        END INTO permission_rank
      FROM item stem_item
      JOIN node_permission an ON an.node_id = stem_item.node_id
      WHERE stem_item.id = item_record.stem_id AND an.user_id = p_user_id;
      
      IF permission_rank < required_rank THEN
        RETURN FALSE;
      END IF;
      
      -- Check ascendant lineage
      SELECT 
        CASE permission
          WHEN 'view' THEN 1
          WHEN 'edit' THEN 2
          WHEN 'admin' THEN 3
        END INTO permission_rank
      FROM item ascn_item
      JOIN node_permission an ON an.node_id = ascn_item.node_id
      WHERE ascn_item.id = item_record.ascn_id AND an.user_id = p_user_id;
      
      IF permission_rank < required_rank THEN
        RETURN FALSE;
      END IF;
    END IF;
  END LOOP;
  
  -- If we get here and found no denials, return original result
  RETURN COALESCE(has_access, FALSE);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on access control tables
ALTER TABLE node_access ENABLE ROW LEVEL SECURITY;

-- Users can see their own access grants and grants they've made
CREATE POLICY "node_access_select_policy" ON node_access
  FOR SELECT
  USING (
    user_id = auth.uid() OR
    -- Can see grants on nodes they admin
    node_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );

-- Only admins can grant access
CREATE POLICY "node_access_insert_policy" ON node_access
  FOR INSERT
  WITH CHECK (
    -- Must be admin of the node
    node_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );

-- Admins can update access grants
CREATE POLICY "node_access_update_policy" ON node_access
  FOR UPDATE
  USING (
    node_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );

-- Admins can revoke access
CREATE POLICY "node_access_delete_policy" ON node_access
  FOR DELETE
  USING (
    node_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );