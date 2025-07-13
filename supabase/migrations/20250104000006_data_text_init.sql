-- Migration: Data table - text

-- =============================================================================
-- ENUM EXTENSION
-- =============================================================================

-- Add 'text' to NodeType enum
ALTER TYPE NodeType ADD VALUE 'text';

-- =============================================================================
-- TABLE DEFINITION
-- =============================================================================

-- Text data table
CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  content TEXT NOT NULL
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Standard indexes
CREATE INDEX index_data_text__node_id ON data_text(node_id);

CREATE INDEX index_data_text__content_fts ON data_text USING gin(to_tsvector('english', content));

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Trigger to update node.updated_at when data changes
CREATE OR REPLACE FUNCTION fn_data_text_update_node()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE node SET updated_at = NOW() WHERE id = NEW.node_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_text_insert_update_update_node
  AFTER INSERT OR UPDATE ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_text_update_node();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on data table
ALTER TABLE data_text ENABLE ROW LEVEL SECURITY;

-- Data policies: access follows node permissions
CREATE POLICY "Users can view text data they have access to" ON data_text
  FOR SELECT
  USING (user_has_node_access(node_id, 4));  -- VIEW permission

CREATE POLICY "Users can insert text data they can edit" ON data_text
  FOR INSERT
  WITH CHECK (user_has_node_access(node_id, 2));  -- EDIT permission

CREATE POLICY "Users can update text data they can edit" ON data_text
  FOR UPDATE
  USING (user_has_node_access(node_id, 2))  -- EDIT permission
  WITH CHECK (user_has_node_access(node_id, 2));

CREATE POLICY "Users can delete text data they admin" ON data_text
  FOR DELETE
  USING (user_has_node_access(node_id, 1));  -- ADMIN permission