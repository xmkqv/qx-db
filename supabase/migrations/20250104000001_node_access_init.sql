-- Migration: Access control tables and views

-- =============================================================================
-- Enums
-- =============================================================================

-- Permission type enum
CREATE TYPE PermissionType AS ENUM ('view', 'edit', 'admin');

-- =============================================================================
-- Custom operators
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
-- Table definitions
-- =============================================================================

-- Node access table (node foreign key will be added later)
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL,  -- Foreign key added in node_init.sql
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE ON UPDATE CASCADE,  -- External auth IDs can change
  permission PermissionType NOT NULL,
  UNIQUE(node_id, user_id)
);

-- Link permissions derived from src node - no separate table needed

-- =============================================================================
-- Indexes
-- =============================================================================

-- Indexes for node_access
CREATE INDEX index_node_access__node_id ON node_access(node_id);
CREATE INDEX index_node_access__user_id ON node_access(user_id);
CREATE INDEX index_node_access__user_id__permission ON node_access(user_id, permission);

-- =============================================================================
-- Views
-- =============================================================================

-- Note: user_workspace_roots view moved to data_user_init.sql after all required tables exist

-- =============================================================================
-- Functions
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
  -- Check if user is creator (has admin access)
  IF EXISTS(SELECT 1 FROM node WHERE id = p_node_id AND creator_id = p_user_id) THEN
    permission_rank := 3; -- admin
  ELSE
    -- Check explicit access
    SELECT 
      CASE permission
        WHEN 'view' THEN 1
        WHEN 'edit' THEN 2
        WHEN 'admin' THEN 3
      END INTO permission_rank
    FROM node_access
    WHERE node_id = p_node_id AND user_id = p_user_id;
  END IF;
  
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
        CASE 
          WHEN n.creator_id = p_user_id THEN 3 -- admin
          ELSE (
            SELECT CASE permission
              WHEN 'view' THEN 1
              WHEN 'edit' THEN 2
              WHEN 'admin' THEN 3
            END
            FROM node_access
            WHERE node_id = stem_item.node_id AND user_id = p_user_id
          )
        END INTO permission_rank
      FROM item stem_item
      JOIN node n ON n.id = stem_item.node_id
      WHERE stem_item.id = item_record.stem_id;
      
      IF permission_rank < required_rank THEN
        RETURN FALSE;
      END IF;
      
      -- Check ascendant lineage
      SELECT 
        CASE 
          WHEN n.creator_id = p_user_id THEN 3 -- admin
          ELSE (
            SELECT CASE permission
              WHEN 'view' THEN 1
              WHEN 'edit' THEN 2
              WHEN 'admin' THEN 3
            END
            FROM node_access
            WHERE node_id = ascn_item.node_id AND user_id = p_user_id
          )
        END INTO permission_rank
      FROM item ascn_item
      JOIN node n ON n.id = ascn_item.node_id
      WHERE ascn_item.id = item_record.ascn_id;
      
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
-- Row level security
-- =============================================================================

-- Enable RLS on access control tables
ALTER TABLE node_access ENABLE ROW LEVEL SECURITY;

-- Basic policies - will be enhanced after node table is created
-- For now, users can only see their own access grants
CREATE POLICY "node_access_select_policy" ON node_access
  FOR SELECT
  USING (
    user_id = auth.uid()
  );

-- Temporarily disable insert/update/delete until node table exists
-- These will be added in the node migration