-- Migration: Node table

-- =============================================================================
-- Enums
-- =============================================================================

CREATE TYPE NodeType AS ENUM ();

-- =============================================================================
-- Table
-- =============================================================================

CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  type NodeType NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX index_node__type ON node(type);
CREATE INDEX index_node__created_at ON node(created_at DESC);
CREATE INDEX index_node__updated_at ON node(updated_at DESC);

-- =============================================================================
-- Triggers
-- =============================================================================

CREATE TRIGGER trigger_node_update_set_updated_at
  BEFORE UPDATE ON node
  FOR EACH ROW
  EXECUTE FUNCTION fn_trigger_set_updated_at();

-- =============================================================================
-- Triggered Functions
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_node_grant_creator_admin()
RETURNS TRIGGER AS $$
BEGIN
  -- Grant admin permission (7 = full access) to the creator
  INSERT INTO node_access (node_id, user_id, permission_bits)
  VALUES (NEW.id, auth.uid(), 7);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_node_insert_grant_admin
  AFTER INSERT ON node
  FOR EACH ROW
  EXECUTE FUNCTION fn_node_grant_creator_admin();

-- =============================================================================
-- Foreign key constraints
-- =============================================================================

-- Add foreign key constraint to node_access now that node table exists
ALTER TABLE node_access 
  ADD CONSTRAINT fk_node_access_node_id 
  FOREIGN KEY (node_id) 
  REFERENCES node(id) 
  ON DELETE CASCADE;


-- =============================================================================
-- Row level security
-- =============================================================================

-- Enable RLS on node table
ALTER TABLE node ENABLE ROW LEVEL SECURITY;

-- Node table policies
CREATE POLICY "Users can view nodes they have access to" ON node
  FOR SELECT
  USING (user_has_node_access(id, 4));  -- VIEW permission

CREATE POLICY "Users can insert nodes" ON node
  FOR INSERT
  WITH CHECK (true);  -- Permission granted via trigger

CREATE POLICY "Users can update nodes they have edit access to" ON node
  FOR UPDATE
  USING (user_has_node_access(id, 2))  -- EDIT permission
  WITH CHECK (user_has_node_access(id, 2));

CREATE POLICY "Users can delete nodes they have admin access to" ON node
  FOR DELETE
  USING (user_has_node_access(id, 1));  -- ADMIN permission

-- =============================================================================
-- Enhanced node_access policies
-- =============================================================================

DROP POLICY "node_access_select_policy" ON node_access;

CREATE POLICY "Users can view access grants they have or admin" ON node_access
  FOR SELECT
  USING (
    user_id = auth.uid() OR
    user_has_node_access(node_id, 1)  -- ADMIN permission
  );

CREATE POLICY "Users can grant access to nodes they admin" ON node_access
  FOR INSERT
  WITH CHECK (
    user_has_node_access(node_id, 1)  -- ADMIN permission
  );

CREATE POLICY "Users can update access grants they admin" ON node_access
  FOR UPDATE
  USING (
    user_has_node_access(node_id, 1)  -- ADMIN permission
  )
  WITH CHECK (
    user_has_node_access(node_id, 1)  -- ADMIN permission
  );

CREATE POLICY "Users can revoke access grants they admin" ON node_access
  FOR DELETE
  USING (
    user_has_node_access(node_id, 1)  -- ADMIN permission
  );