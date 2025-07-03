-- Add data_user table for user profiles with authentication linkage

-- 1. Add to NODETYPE enum
ALTER TYPE NODETYPE ADD VALUE 'user';

-- 2. Create table with standard pattern
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- user-specific fields
  user_id UUID UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  preferences JSONB DEFAULT '{}',
  
  CONSTRAINT data_user_node_unique UNIQUE (node_id)
);

-- 3. Standard indexes and triggers
CREATE INDEX idx_data_user_node_id ON data_user (node_id);
CREATE INDEX idx_data_user_user_id ON data_user (user_id);
CREATE INDEX idx_data_user_username ON data_user (username);

CREATE TRIGGER data_user_trigger_updated_at
  BEFORE UPDATE ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- 4. Type-specific node creation trigger
CREATE OR REPLACE FUNCTION trigger_data_user_insert()
  RETURNS TRIGGER AS $$
BEGIN
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type, creator_id) 
    VALUES ('user'::NODETYPE, COALESCE(NEW.user_id, auth.uid()))
    RETURNING id INTO NEW.node_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER data_user_trigger_insert_node
  BEFORE INSERT ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_user_insert();

-- 5. Standard RLS
ALTER TABLE data_user ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Data follows node access" ON data_user
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_user.node_id 
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
  ) THEN
    RAISE EXCEPTION 'Node % must have corresponding data in a data_* table', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;