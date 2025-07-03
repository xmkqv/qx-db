-- Add data_memo table for conversation/cluster containers

-- Add memo type enum
CREATE TYPE MEMOTYPE AS ENUM (
  'chat'
);

-- 1. Add to NODETYPE enum
ALTER TYPE NODETYPE ADD VALUE 'memo';

-- 2. Create table with standard pattern
CREATE TABLE data_memo (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- memo-specific fields
  item_id INTEGER NOT NULL REFERENCES item (id) ON DELETE CASCADE,
  memo_type MEMOTYPE NOT NULL,
  
  CONSTRAINT data_memo_node_unique UNIQUE (node_id)
);

-- 3. Standard indexes and triggers
CREATE INDEX idx_data_memo_node_id ON data_memo (node_id);
CREATE INDEX idx_data_memo_item_id ON data_memo (item_id);
CREATE INDEX idx_data_memo_type ON data_memo (memo_type);

CREATE TRIGGER data_memo_trigger_updated_at
  BEFORE UPDATE ON data_memo
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- 4. Type-specific node creation trigger
CREATE OR REPLACE FUNCTION trigger_data_memo_insert()
  RETURNS TRIGGER AS $$
BEGIN
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type, creator_id) 
    VALUES ('memo'::NODETYPE, auth.uid())
    RETURNING id INTO NEW.node_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER data_memo_trigger_insert_node
  BEFORE INSERT ON data_memo
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_memo_insert();

-- 5. Standard RLS
ALTER TABLE data_memo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Data follows node access" ON data_memo
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_memo.node_id 
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
    UNION ALL
    SELECT 1 FROM data_user WHERE node_id = NEW.id
    UNION ALL
    SELECT 1 FROM data_memo WHERE node_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Node % must have corresponding data in a data_* table', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;