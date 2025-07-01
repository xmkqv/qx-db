--
--
--
CREATE OR REPLACE FUNCTION trigger_set_updated_at ()
  RETURNS TRIGGER
  AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

--
-- node
--
CREATE TYPE NODETYPE AS ENUM (
  'file',
  'text',
  'user',
  'memo'
);

CREATE TYPE MEMOTYPE AS ENUM (
  'chat'
);

CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  type NODETYPE NOT NULL,
  creator_id UUID REFERENCES auth.users (id) ON DELETE SET NULL
);

CREATE INDEX node_index_type ON node (type);

CREATE INDEX node_index_created_at ON node (created_at DESC);

CREATE INDEX node_index_updated_at ON node (updated_at DESC);

CREATE INDEX node_index_creator_id ON node (creator_id) WHERE creator_id IS NOT NULL;

CREATE TRIGGER node_trigger_updated_at
  BEFORE UPDATE ON node
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

--
-- Access control
--
CREATE TABLE node_access (
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  permission TEXT NOT NULL CHECK (permission IN ('view', 'edit', 'admin')),
  granted_at TIMESTAMP DEFAULT NOW(),
  granted_by UUID REFERENCES auth.users (id) ON DELETE SET NULL,
  PRIMARY KEY (node_id, user_id)
);

CREATE INDEX idx_node_access_user ON node_access (user_id, permission);
CREATE INDEX idx_node_access_node ON node_access (node_id);

-- View for fast access checks
CREATE VIEW accessible_nodes AS
SELECT DISTINCT node_id, user_id, permission FROM (
  -- Explicit grants
  SELECT node_id, user_id, permission FROM node_access
  UNION ALL
  -- Creator access
  SELECT id, creator_id, 'admin'::TEXT FROM node WHERE creator_id IS NOT NULL
) access_union;

--
-- link
--
CREATE TABLE link (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  src_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  dst_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  CHECK (src_id != dst_id),
  UNIQUE (src_id, dst_id)
);

CREATE INDEX link_index_src_id ON link (src_id);

CREATE INDEX link_index_dst_id ON link (dst_id);

CREATE INDEX link_index_created_at ON link (created_at DESC);

CREATE TRIGGER link_trigger_updated_at
  BEFORE UPDATE ON link
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE OR REPLACE FUNCTION get_dsts (src_id INTEGER)
  RETURNS SETOF node
  AS $$
BEGIN
  RETURN QUERY
  SELECT
    n.*
  FROM
    link l
    JOIN node n ON l.dst_id = n.id
  WHERE
    l.src_id = get_dsts.src_id;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_srcs (dst_id INTEGER)
  RETURNS SETOF node
  AS $$
BEGIN
  RETURN QUERY
  SELECT
    n.*
  FROM
    link l
    JOIN node n ON l.src_id = n.id
  WHERE
    l.dst_id = get_srcs.dst_id;
END;
$$
LANGUAGE plpgsql;

--
-- tile
--
CREATE TYPE ANCHOR AS ENUM (
  'lhs',
  'rhs',
  'flow'
);

CREATE TYPE VISUAL AS ENUM (
  'sec',
  'doc',
  'dir'
);

CREATE TYPE LAYOUT AS ENUM (
  'panel',
  'slideshow'
);

-- both are required, such that tiles not in flow but in a view
CREATE TABLE tile (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  x REAL NOT NULL,
  y REAL NOT NULL,
  w REAL NOT NULL,
  h REAL NOT NULL,
  viewboxX REAL NOT NULL,
  viewboxY REAL NOT NULL,
  viewboxZoom REAL NOT NULL,
  layout LAYOUT,
  visual VISUAL,
  anchor ANCHOR,
  motion BOOLEAN DEFAULT FALSE,
  active BOOLEAN DEFAULT FALSE,
  -- CSS style properties
  style JSONB
);

CREATE INDEX tile_index_anchor ON tile (anchor) WHERE anchor IS NOT NULL;

CREATE INDEX tile_index_visual ON tile (visual) WHERE visual IS NOT NULL;

CREATE INDEX tile_index_layout ON tile (layout) WHERE layout IS NOT NULL;

CREATE INDEX tile_index_active ON tile (active) WHERE active = TRUE;

CREATE INDEX tile_index_position ON tile (x, y);

CREATE TRIGGER tile_trigger_updated_at
  BEFORE UPDATE ON tile
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

--
-- item
--
CREATE TABLE item (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  desc_id INTEGER REFERENCES item (id) ON DELETE CASCADE,
  next_id INTEGER REFERENCES item (id) ON DELETE SET NULL,
  tile_id INTEGER NOT NULL REFERENCES tile (id) ON DELETE CASCADE,
  CHECK (id != desc_id),
  CHECK (id != next_id)
);

CREATE INDEX item_index_desc_id ON item (desc_id);

CREATE INDEX item_index_next_id ON item (next_id);

CREATE INDEX item_index_node_id ON item (node_id);

CREATE INDEX item_index_tile_id ON item (tile_id);

CREATE INDEX item_index_root ON item (desc_id, next_id)
WHERE
  desc_id IS NULL AND next_id IS NULL;

CREATE INDEX item_index_peers ON item (desc_id, next_id);

CREATE TRIGGER item_trigger_updated_at
  BEFORE UPDATE ON item
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

-- Ensure each tile is associated with only one item
ALTER TABLE item ADD CONSTRAINT item_tile_unique UNIQUE (tile_id);

-- Function to get all neighbors of a node (linked nodes and descendant items)
CREATE OR REPLACE FUNCTION get_nbrs(node_id INTEGER)
  RETURNS TABLE (
    neighbor_id INTEGER,
    relationship_type TEXT
  ) AS $$
BEGIN
  RETURN QUERY
  -- Linked nodes (as destination)
  SELECT dst_id AS neighbor_id, 'link_dst'::TEXT AS relationship_type
  FROM link WHERE src_id = get_nbrs.node_id
  UNION ALL
  -- Linked nodes (as source)
  SELECT src_id AS neighbor_id, 'link_src'::TEXT AS relationship_type
  FROM link WHERE dst_id = get_nbrs.node_id
  UNION ALL
  -- Descendant items
  SELECT i2.node_id AS neighbor_id, 'descendant'::TEXT AS relationship_type
  FROM item i1
  JOIN item i2 ON i2.desc_id = i1.id
  WHERE i1.node_id = get_nbrs.node_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_items (item_id INTEGER, variants JSONB DEFAULT NULL)
  RETURNS SETOF item
  AS $$
BEGIN
  RETURN QUERY
  SELECT
    *
  FROM
    item
  WHERE
    id = get_items.item_id;
END;
$$
LANGUAGE plpgsql;

----------- DATA -------------------------------------------------------------
CREATE TYPE FILETYPE AS ENUM (
  'csv',
  'png',
  'md'
);

CREATE TABLE data_file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  type FILETYPE NOT NULL,
  bytes BYTEA NOT NULL,
  uri TEXT NOT NULL
);

CREATE TRIGGER data_file_trigger_updated_at
  BEFORE UPDATE ON data_file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_data_file_node_id ON data_file (node_id);

CREATE INDEX idx_data_file_type ON data_file (type);

CREATE INDEX idx_data_file_uri ON data_file (uri);

CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  content TEXT NOT NULL
);

CREATE TRIGGER data_text_trigger_updated_at
  BEFORE UPDATE ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_data_text_node_id ON data_text (node_id);

-- Add full-text search index on text content
CREATE INDEX idx_data_text_content_fts ON data_text USING gin
  (TO_TSVECTOR('english', content));

-- User data type with authentication linkage
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  user_id UUID UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  -- User-specific fields
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  preferences JSONB DEFAULT '{}',
  -- Constraints
  CONSTRAINT data_user_node_unique UNIQUE (node_id)
);

CREATE TRIGGER data_user_trigger_updated_at
  BEFORE UPDATE ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_data_user_node_id ON data_user (node_id);
CREATE INDEX idx_data_user_user_id ON data_user (user_id);
CREATE INDEX idx_data_user_username ON data_user (username);

-- Memo data type for conversation/cluster containers
CREATE TABLE data_memo (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- Entry point to item tree
  item_id INTEGER NOT NULL REFERENCES item (id) ON DELETE CASCADE,
  
  -- Memo categorization
  memo_type MEMOTYPE NOT NULL,
  
  CONSTRAINT data_memo_node_unique UNIQUE (node_id)
);

CREATE TRIGGER data_memo_trigger_updated_at
  BEFORE UPDATE ON data_memo
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

CREATE INDEX idx_data_memo_node_id ON data_memo (node_id);
CREATE INDEX idx_data_memo_item_id ON data_memo (item_id);
CREATE INDEX idx_data_memo_type ON data_memo (memo_type);

-- Individual trigger functions for each data type
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

CREATE TRIGGER data_text_trigger_insert_node
  BEFORE INSERT ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_text_insert();

CREATE TRIGGER data_file_trigger_insert_node
  BEFORE INSERT ON data_file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_file_insert();

CREATE TRIGGER data_user_trigger_insert_node
  BEFORE INSERT ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_user_insert();

CREATE TRIGGER data_memo_trigger_insert_node
  BEFORE INSERT ON data_memo
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_memo_insert();

-- Constraint: No node can exist without data
-- This is enforced through a deferred constraint check function
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
    RAISE EXCEPTION 'Node % must have corresponding data in data_text, data_file, data_user, or data_memo table', NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply constraint check on node insert/update
-- Note: This is deferred to allow for transaction-level consistency
CREATE CONSTRAINT TRIGGER node_must_have_data_trigger
  AFTER INSERT OR UPDATE ON node
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION check_node_has_data();

--
-- Live query function for frontend
--
CREATE OR REPLACE FUNCTION live_user_nodes(
  include_data BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
  -- Node fields
  id INTEGER,
  type NODETYPE,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  creator_id UUID,
  permission TEXT,
  -- Data fields (when requested)
  data JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    n.id,
    n.type,
    n.created_at,
    n.updated_at,
    n.creator_id,
    an.permission,
    CASE 
      WHEN include_data AND n.type = 'text' THEN 
        jsonb_build_object('content', dt.content, 'node_id', dt.node_id)
      WHEN include_data AND n.type = 'file' THEN
        jsonb_build_object('uri', df.uri, 'type', df.type, 'bytes', df.bytes, 'node_id', df.node_id)
      WHEN include_data AND n.type = 'user' THEN
        jsonb_build_object(
          'username', du.username, 
          'display_name', du.display_name,
          'bio', du.bio,
          'avatar_url', du.avatar_url,
          'preferences', du.preferences,
          'node_id', du.node_id
        )
      WHEN include_data AND n.type = 'memo' THEN
        jsonb_build_object(
          'memo_type', dm.memo_type,
          'item_id', dm.item_id,
          'node_id', dm.node_id
        )
    END as data
  FROM node n
  JOIN accessible_nodes an ON n.id = an.node_id
  LEFT JOIN data_text dt ON include_data AND n.id = dt.node_id
  LEFT JOIN data_file df ON include_data AND n.id = df.node_id  
  LEFT JOIN data_user du ON include_data AND n.id = du.node_id
  LEFT JOIN data_memo dm ON include_data AND n.id = dm.node_id
  WHERE an.user_id = auth.uid()
  ORDER BY n.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION live_user_nodes TO authenticated;

--
-- Row Level Security Policies
--

-- Enable RLS on all tables
ALTER TABLE node ENABLE ROW LEVEL SECURITY;
ALTER TABLE node_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE link ENABLE ROW LEVEL SECURITY;
ALTER TABLE item ENABLE ROW LEVEL SECURITY;
ALTER TABLE tile ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_text ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_file ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_memo ENABLE ROW LEVEL SECURITY;

-- Node policies
CREATE POLICY "Users see accessible nodes" ON node
  FOR SELECT
  USING (
    id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert their own nodes" ON node
  FOR INSERT
  WITH CHECK (creator_id = auth.uid());

CREATE POLICY "Users can update their accessible nodes" ON node
  FOR UPDATE
  USING (
    id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    )
  );

CREATE POLICY "Users can delete their admin nodes" ON node
  FOR DELETE
  USING (
    id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid() 
      AND permission = 'admin'
    )
  );

-- Node access policies
CREATE POLICY "Users see their access grants" ON node_access
  FOR SELECT
  USING (user_id = auth.uid() OR granted_by = auth.uid());

CREATE POLICY "Admins can grant access" ON node_access
  FOR INSERT
  WITH CHECK (
    granted_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = node_access.node_id
      AND user_id = auth.uid()
      AND permission = 'admin'
    )
  );

-- Data table policies (cascade from node)
CREATE POLICY "Data follows node access" ON data_text
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_text.node_id 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY "Data follows node access" ON data_file
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_file.node_id 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY "Data follows node access" ON data_user
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_user.node_id 
      AND user_id = auth.uid()
    )
  );

CREATE POLICY "Data follows node access" ON data_memo
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_memo.node_id 
      AND user_id = auth.uid()
    )
  );

-- Link policies
CREATE POLICY "Users see links between accessible nodes" ON link
  FOR SELECT
  USING (
    src_id IN (SELECT node_id FROM accessible_nodes WHERE user_id = auth.uid()) AND
    dst_id IN (SELECT node_id FROM accessible_nodes WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can create links between editable nodes" ON link
  FOR INSERT
  WITH CHECK (
    src_id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    ) AND
    dst_id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    )
  );

-- Tile and Item policies (for now, follow node access)
CREATE POLICY "Tiles follow node access" ON tile
  FOR ALL
  USING (
    id IN (
      SELECT tile_id FROM item i
      WHERE i.node_id IN (
        SELECT node_id FROM accessible_nodes 
        WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Items follow node access" ON item
  FOR ALL
  USING (
    node_id IN (
      SELECT node_id FROM accessible_nodes 
      WHERE user_id = auth.uid()
    )
  );
