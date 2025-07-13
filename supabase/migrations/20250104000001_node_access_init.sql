-- Migration: Access control tables and views

-- =============================================================================
-- Table definitions
-- =============================================================================

-- Node access table (node foreign key will be added later)
CREATE TABLE node_access (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL,  -- Foreign key added in node_init.sql
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE ON UPDATE CASCADE,  -- External auth IDs can change
  permission_bits INTEGER NOT NULL DEFAULT 4,  -- Default to view-only
  UNIQUE(node_id, user_id),
  CHECK (permission_bits >= 0 AND permission_bits <= 7)
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX index_node_access__node_id ON node_access(node_id);
CREATE INDEX index_node_access__user_id ON node_access(user_id);
CREATE INDEX index_node_access__user_id__permission ON node_access(user_id, permission);

-- =============================================================================
-- Functions
-- =============================================================================

-- Check if user has access to a node with required permission bits
CREATE OR REPLACE FUNCTION user_has_node_access(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY INVOKER
AS $$
  SELECT EXISTS (
    -- User has explicit access with required permission bits
    SELECT 1 FROM node_access
    WHERE node_id = p_node_id 
    AND user_id = auth.uid()
    AND (permission_bits & p_required_bits) = p_required_bits
  );
$$;


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