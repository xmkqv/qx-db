-- Migration: Node table

-- =============================================================================
-- Enums
-- =============================================================================

-- Core enum for node types (extended by data migrations)
CREATE TYPE NodeType AS ENUM ();

-- =============================================================================
-- Table definition
-- =============================================================================

-- Node table with auto-incrementing IDs
CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  type NodeType NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  creator_id UUID REFERENCES auth.users(id) ON DELETE SET NULL ON UPDATE CASCADE,  -- External auth IDs can change
  -- Generated column for common queries
  is_owned BOOLEAN GENERATED ALWAYS AS (creator_id IS NOT NULL) STORED
);

-- =============================================================================
-- Indexes
-- =============================================================================
CREATE INDEX index_node__type ON node(type);
CREATE INDEX index_node__creator_id ON node(creator_id) WHERE creator_id IS NOT NULL;
CREATE INDEX index_node__created_at ON node(created_at DESC);
CREATE INDEX index_node__updated_at ON node(updated_at DESC);
-- Index for generated column
CREATE INDEX index_node__is_owned ON node(is_owned) WHERE is_owned = true;

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
-- Triggers
-- =============================================================================

-- Trigger for updated_at
CREATE TRIGGER trigger_node_update_set_updated_at
  BEFORE UPDATE ON node
  FOR EACH ROW
  EXECUTE FUNCTION fn_trigger_set_updated_at();

-- =============================================================================
-- Row level security
-- =============================================================================

-- Enable RLS on node table
ALTER TABLE node ENABLE ROW LEVEL SECURITY;

-- Node table policies
CREATE POLICY "node_select_policy" ON node
  FOR SELECT
  USING (
    creator_id = auth.uid() OR
    id IN (
      SELECT node_id FROM node_access 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "node_insert_policy" ON node
  FOR INSERT
  WITH CHECK (
    creator_id = auth.uid()
  );

CREATE POLICY "node_update_policy" ON node
  FOR UPDATE
  USING (
    creator_id = auth.uid() OR
    id IN (
      SELECT node_id FROM node_access 
      WHERE user_id = auth.uid() 
      AND permission >= 'edit'::PermissionType
    )
  )
  WITH CHECK (
    -- Ensure creator_id and type cannot be changed
    creator_id = auth.uid() OR
    id IN (
      SELECT node_id FROM node_access 
      WHERE user_id = auth.uid() 
      AND permission >= 'edit'::PermissionType
    )
  );

CREATE POLICY "node_delete_policy" ON node
  FOR DELETE
  USING (
    creator_id = auth.uid() OR
    id IN (
      SELECT node_id FROM node_access 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'::PermissionType
    )
  );

-- =============================================================================
-- Enhanced node_access policies
-- =============================================================================

-- Drop the basic select policy
DROP POLICY "node_access_select_policy" ON node_access;

-- Create enhanced policies now that node table exists
CREATE POLICY "node_access_select_policy" ON node_access
  FOR SELECT
  USING (
    user_id = auth.uid() OR
    -- Can see grants on nodes they own or admin
    EXISTS (
      SELECT 1 FROM node n 
      WHERE n.id = node_access.node_id 
      AND n.creator_id = auth.uid()
    ) OR
    node_id IN (
      SELECT na2.node_id FROM node_access na2
      WHERE na2.user_id = auth.uid() 
      AND na2.permission = 'admin'
    )
  );

-- Only node owners and admins can grant access
CREATE POLICY "node_access_insert_policy" ON node_access
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM node n 
      WHERE n.id = node_access.node_id 
      AND n.creator_id = auth.uid()
    ) OR
    node_id IN (
      SELECT na2.node_id FROM node_access na2
      WHERE na2.user_id = auth.uid() 
      AND na2.permission = 'admin'
    )
  );

-- Node owners and admins can update access grants
CREATE POLICY "node_access_update_policy" ON node_access
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM node n 
      WHERE n.id = node_access.node_id 
      AND n.creator_id = auth.uid()
    ) OR
    node_id IN (
      SELECT na2.node_id FROM node_access na2
      WHERE na2.user_id = auth.uid() 
      AND na2.permission = 'admin'
    )
  );

-- Node owners and admins can revoke access
CREATE POLICY "node_access_delete_policy" ON node_access
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM node n 
      WHERE n.id = node_access.node_id 
      AND n.creator_id = auth.uid()
    ) OR
    node_id IN (
      SELECT na2.node_id FROM node_access na2
      WHERE na2.user_id = auth.uid() 
      AND na2.permission = 'admin'
    )
  );