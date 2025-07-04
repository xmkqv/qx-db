-- Migration: Data table - user

-- =============================================================================
-- ENUM EXTENSION
-- =============================================================================

-- Add 'user' to NodeType enum
ALTER TYPE NodeType ADD VALUE 'user';

-- =============================================================================
-- TABLE DEFINITION
-- =============================================================================

-- User data table with root item reference
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  user_id UUID NOT NULL UNIQUE,  -- Auth system ID
  username TEXT NOT NULL UNIQUE,
  bio TEXT,
  head_item_id INTEGER REFERENCES item(id) ON DELETE SET NULL  -- User's tree head
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Standard indexes
CREATE INDEX index_data_user__node_id ON data_user(node_id);
CREATE INDEX index_data_user__user_id ON data_user(user_id);
CREATE INDEX index_data_user__username ON data_user(username);
CREATE INDEX index_data_user__head_item_id ON data_user(head_item_id) WHERE head_item_id IS NOT NULL;

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Function to automatically create head item for new users
CREATE OR REPLACE FUNCTION fn_data_user_create_head_item()
RETURNS TRIGGER AS $$
DECLARE
  new_node_id INTEGER;
  new_item_id INTEGER;
  new_tile_id INTEGER;
BEGIN
  -- Only create if head_item_id is NULL
  IF NEW.head_item_id IS NULL THEN
    -- Create a node for the root item
    INSERT INTO node (type, creator_id) 
    VALUES ('text'::NodeType, NEW.user_id)
    RETURNING id INTO new_node_id;
    
    -- Create text data for the node
    INSERT INTO data_text (node_id, content)
    VALUES (new_node_id, NEW.username || '''s workspace');
    
    -- Create a tile for visualization
    INSERT INTO tile (x, y, w, h)
    VALUES (0, 0, 200, 100)
    RETURNING id INTO new_tile_id;
    
    -- Create the root item (ascn_id = NULL makes it a root)
    INSERT INTO item (node_id, ascn_id, tile_id)
    VALUES (new_node_id, NULL, new_tile_id)
    RETURNING id INTO new_item_id;
    
    -- Update the user's head_item_id
    NEW.head_item_id := new_item_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_user_insert_create_head_item
  BEFORE INSERT ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_user_create_head_item();

-- Trigger to update node.updated_at when user data changes
CREATE OR REPLACE FUNCTION fn_data_user_update_node()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE node SET updated_at = NOW() WHERE id = NEW.node_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_user_update_update_node
  AFTER UPDATE ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_user_update_node();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on data table
ALTER TABLE data_user ENABLE ROW LEVEL SECURITY;

-- Users see accessible user data OR their own data
CREATE POLICY "Users see accessible user data" ON data_user
  FOR SELECT
  USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM node_permission
      WHERE node_id = data_user.node_id 
      AND user_id = auth.uid()
    )
  );

-- Users can only update their own user data
CREATE POLICY "Users update own data" ON data_user
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Users can insert their own user data
CREATE POLICY "Users insert own data" ON data_user
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can delete based on node permissions
CREATE POLICY "Users delete user data" ON data_user
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM node_permission
      WHERE node_id = data_user.node_id 
      AND user_id = auth.uid()
      AND permission = 'admin'
    )
  );