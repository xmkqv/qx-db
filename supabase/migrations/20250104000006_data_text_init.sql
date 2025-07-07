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

-- Standard policy: check permissions directly
CREATE POLICY "Data follows node access" ON data_text
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM node n
      WHERE n.id = data_text.node_id 
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