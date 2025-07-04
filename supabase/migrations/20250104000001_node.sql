-- Migration: Node table

-- =============================================================================
-- ENUMS
-- =============================================================================

-- Core enum for node types (extended by data_* migrations)
CREATE TYPE NodeType AS ENUM ();  -- Empty, will be extended by data_* migrations

-- =============================================================================
-- TABLE DEFINITION
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
-- INDEXES
-- =============================================================================

-- Indexes for node table
CREATE INDEX index_node__type ON node(type);
CREATE INDEX index_node__creator_id ON node(creator_id) WHERE creator_id IS NOT NULL;
CREATE INDEX index_node__created_at ON node(created_at DESC);
CREATE INDEX index_node__updated_at ON node(updated_at DESC);
-- Index for generated column
CREATE INDEX index_node__is_owned ON node(is_owned) WHERE is_owned = true;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Trigger for updated_at
CREATE TRIGGER trigger_node_update_set_updated_at
  BEFORE UPDATE ON node
  FOR EACH ROW
  EXECUTE FUNCTION fn_trigger_set_updated_at();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on node table
ALTER TABLE node ENABLE ROW LEVEL SECURITY;

-- Node table policies
CREATE POLICY "node_select_policy" ON node
  FOR SELECT
  USING (
    id IN (
      SELECT node_id FROM node_permission 
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
    id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission >= 'edit'::PermissionType
    )
  )
  WITH CHECK (
    (OLD.creator_id IS NOT DISTINCT FROM NEW.creator_id) AND
    (OLD.type IS NOT DISTINCT FROM NEW.type)
  );

CREATE POLICY "node_delete_policy" ON node
  FOR DELETE
  USING (
    id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission >= 'admin'::PermissionType
    )
  );