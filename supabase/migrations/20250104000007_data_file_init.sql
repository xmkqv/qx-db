-- Migration: Data table - file

-- =============================================================================
-- ENUMS
-- =============================================================================

-- File types supported by the system
CREATE TYPE FileType AS ENUM ('png');

-- =============================================================================
-- ENUM EXTENSION
-- =============================================================================

-- Add 'file' to NodeType enum
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

-- Standard policy: check permissions directly
CREATE POLICY "Data follows node access" ON data_file
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM node n
      WHERE n.id = data_file.node_id 
      AND (
        n.creator_id = auth.uid() OR
        EXISTS (
          SELECT 1 FROM node_access na
          WHERE na.node_id = n.id
          AND na.user_id = auth.uid()
        )
      )
    )
  );