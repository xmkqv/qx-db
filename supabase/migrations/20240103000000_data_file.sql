-- Add data_file table for storing file metadata

-- Add file type enum
CREATE TYPE FILETYPE AS ENUM (
  'csv',
  'png',
  'md'
);

-- 1. Add to NODETYPE enum
ALTER TYPE NODETYPE ADD VALUE 'file';

-- 2. Create table with standard pattern
CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- file-specific fields
  type FILETYPE NOT NULL,
  bytea BYTEA NOT NULL,
  uri TEXT NOT NULL,
  
  CONSTRAINT data_file_node_unique UNIQUE (node_id)
);

-- 3. Standard indexes and triggers
CREATE INDEX idx_data_file_node_id ON data_file (node_id);
CREATE INDEX idx_data_file_type ON data_file (type);
CREATE INDEX idx_data_file_uri ON data_file (uri);

CREATE TRIGGER data_file_trigger_updated_at
  BEFORE UPDATE ON data_file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- 4. Type-specific node creation trigger
CREATE OR REPLACE FUNCTION trigger_data_file_insert()
  RETURNS TRIGGER AS $$
BEGIN
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type, creator_id) 
    VALUES ('file'::NODETYPE, auth.uid())
    RETURNING id INTO NEW.node_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER data_file_trigger_insert_node
  BEFORE INSERT ON data_file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_file_insert();

-- 5. Standard RLS
ALTER TABLE data_file ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Data follows node access" ON data_file
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_file.node_id 
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
    UNION ALL
    SELECT 1 FROM data_file WHERE node_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Node % must have corresponding data in a data_* table', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;