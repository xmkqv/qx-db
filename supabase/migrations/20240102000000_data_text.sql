-- Add data_text table for storing text content

-- 1. Add to NODETYPE enum
ALTER TYPE NODETYPE ADD VALUE 'text';

-- 2. Create table with standard pattern
CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- text-specific fields
  content TEXT NOT NULL,
  
  CONSTRAINT data_text_node_unique UNIQUE (node_id)
);

-- 3. Standard indexes and triggers
CREATE INDEX idx_data_text_node_id ON data_text (node_id);

-- Add full-text search index on text content
CREATE INDEX idx_data_text_content_fts ON data_text USING gin
  (TO_TSVECTOR('english', content));

CREATE TRIGGER data_text_trigger_updated_at
  BEFORE UPDATE ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- 4. Type-specific node creation trigger
CREATE OR REPLACE FUNCTION trigger_data_text_insert()
  RETURNS TRIGGER AS $$
BEGIN
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type, creator_id) 
    VALUES ('text'::NODETYPE, auth.uid())
    RETURNING id INTO NEW.node_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER data_text_trigger_insert_node
  BEFORE INSERT ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_text_insert();

-- 5. Standard RLS
ALTER TABLE data_text ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Data follows node access" ON data_text
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_text.node_id 
      AND user_id = auth.uid()
    )
  );

-- Update check_node_has_data() function
CREATE OR REPLACE FUNCTION check_node_has_data()
  RETURNS TRIGGER AS $$
BEGIN
  -- Check if the node has corresponding data
  IF NOT EXISTS (
    SELECT 1 FROM data_text WHERE node_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Node % must have corresponding data in a data_* table', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'node_must_have_data_trigger'
  ) THEN
    CREATE CONSTRAINT TRIGGER node_must_have_data_trigger
      AFTER INSERT OR UPDATE ON node
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW
      EXECUTE FUNCTION check_node_has_data();
  END IF;
END $$;