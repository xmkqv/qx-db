-- Migration: Data table - file

-- =============================================================================
-- ENUMS & ENUM EXTENSION
-- =============================================================================

CREATE TYPE FileType AS ENUM ('png');

ALTER TYPE NodeType ADD VALUE 'file';

-- =============================================================================
-- TABLE DEFINITION
-- =============================================================================

-- File data table
CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  type FileType NOT NULL,
  bytea BYTEA NOT NULL -- bytea field name explicitly chosen to avoid name conflicts in clients
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Standard indexes
CREATE INDEX index_data_file__node_id ON data_file(node_id);
CREATE INDEX index_data_file__type ON data_file(type);

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Trigger to update node.updated_at when file data changes
CREATE OR REPLACE FUNCTION fn_data_file_update_node()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE node SET updated_at = NOW() WHERE id = NEW.node_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_file_insert_update_update_node
  AFTER INSERT OR UPDATE ON data_file
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_file_update_node();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on data table
ALTER TABLE data_file ENABLE ROW LEVEL SECURITY;

-- Data policies: access follows node permissions
CREATE POLICY "Users can view file data they have access to" ON data_file
  FOR SELECT
  USING (user_has_node_access(node_id, 4));  -- VIEW permission

CREATE POLICY "Users can insert file data they can edit" ON data_file
  FOR INSERT
  WITH CHECK (user_has_node_access(node_id, 2));  -- EDIT permission

CREATE POLICY "Users can update file data they can edit" ON data_file
  FOR UPDATE
  USING (user_has_node_access(node_id, 2))  -- EDIT permission
  WITH CHECK (user_has_node_access(node_id, 2));

CREATE POLICY "Users can delete file data they admin" ON data_file
  FOR DELETE
  USING (user_has_node_access(node_id, 1));  -- ADMIN permission