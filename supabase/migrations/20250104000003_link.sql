-- Migration: Link table

-- =============================================================================
-- TABLE DEFINITION
-- =============================================================================

-- Link table with integer references
CREATE TABLE link (
  id SERIAL PRIMARY KEY,
  src_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  dst_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  CHECK (src_id != dst_id)  -- No self-links
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Indexes for link table
CREATE INDEX index_link__src_id ON link(src_id);
CREATE INDEX index_link__dst_id ON link(dst_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on link table
ALTER TABLE link ENABLE ROW LEVEL SECURITY;

-- Link permissions derived from src node
CREATE POLICY "link_select_policy" ON link
  FOR SELECT
  USING (
    src_id IN (SELECT node_id FROM node_permission WHERE user_id = auth.uid())
  );

CREATE POLICY "link_insert_policy" ON link
  FOR INSERT
  WITH CHECK (
    src_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    )
  );

CREATE POLICY "link_update_policy" ON link
  FOR UPDATE
  USING (
    src_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    )
  );

CREATE POLICY "link_delete_policy" ON link
  FOR DELETE
  USING (
    src_id IN (
      SELECT node_id FROM node_permission 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );