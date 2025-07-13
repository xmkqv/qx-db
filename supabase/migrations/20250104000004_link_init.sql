-- Migration: Link table

-- =============================================================================
-- Table definition
-- =============================================================================

CREATE TABLE link (
  id SERIAL PRIMARY KEY,
  src_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  dst_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  CHECK (src_id != dst_id)  -- No self-links
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX index_link__src_id ON link(src_id);
CREATE INDEX index_link__dst_id ON link(dst_id);

-- =============================================================================
-- Row level security
-- =============================================================================

ALTER TABLE link ENABLE ROW LEVEL SECURITY;

-- Link permissions derived from src node
CREATE POLICY "Users can view links from nodes they have access to" ON link
  FOR SELECT
  USING (user_has_node_access(src_id, 4));  -- VIEW permission

CREATE POLICY "Users can create links from nodes they can edit" ON link
  FOR INSERT
  WITH CHECK (user_has_node_access(src_id, 2));  -- EDIT permission

CREATE POLICY "Users can update links from nodes they can edit" ON link
  FOR UPDATE
  USING (user_has_node_access(src_id, 2))  -- EDIT permission
  WITH CHECK (user_has_node_access(src_id, 2));

CREATE POLICY "Users can delete links from nodes they admin" ON link
  FOR DELETE
  USING (user_has_node_access(src_id, 1));  -- ADMIN permission