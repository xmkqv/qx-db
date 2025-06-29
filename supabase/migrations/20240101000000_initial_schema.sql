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
  'user'
);

CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  type NODETYPE NOT NULL
);

CREATE INDEX node_index_type ON node (type);

CREATE INDEX node_index_created_at ON node (created_at DESC);

CREATE INDEX node_index_updated_at ON node (updated_at DESC);

CREATE TRIGGER node_trigger_updated_at
  BEFORE UPDATE ON node
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

--
-- root (bare essentials for auth)
--
CREATE TABLE root (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  email TEXT UNIQUE
);

CREATE UNIQUE INDEX root_index_node_id_unique ON root (node_id);

CREATE INDEX root_index_user_id ON root (user_id);

CREATE INDEX root_index_email ON root (email) WHERE email IS NOT NULL;

CREATE TRIGGER root_trigger_updated_at
  BEFORE UPDATE ON root
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

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

CREATE TABLE file (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  type FILETYPE NOT NULL,
  bytes BYTEA NOT NULL,
  uri TEXT NOT NULL
);

CREATE TRIGGER file_trigger_updated_at
  BEFORE UPDATE ON file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_file_node_id ON file (node_id);

CREATE INDEX idx_file_type ON file (type);

CREATE INDEX idx_file_uri ON file (uri);

CREATE TABLE text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  content TEXT NOT NULL
);

CREATE TRIGGER text_trigger_updated_at
  BEFORE UPDATE ON text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_text_node_id ON text (node_id);

-- Add full-text search index on text content
CREATE INDEX idx_text_content_fts ON text USING gin
  (TO_TSVECTOR('english', content));

-- User data type
CREATE TABLE data_user (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  -- User-specific fields
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  bio TEXT,
  avatar_url TEXT,
  preferences JSONB DEFAULT '{}',
  -- Additional metadata
  CONSTRAINT data_user_node_unique UNIQUE (node_id)
);

CREATE TRIGGER data_user_trigger_updated_at
  BEFORE UPDATE ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_data_user_node_id ON data_user (node_id);
CREATE INDEX idx_data_user_username ON data_user (username);

-- Trigger to automatically create node on data insert
CREATE OR REPLACE FUNCTION trigger_data_insert()
  RETURNS TRIGGER AS $$
BEGIN
  -- Insert node first if node_id is not provided
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type) 
    VALUES (
      CASE 
        WHEN TG_TABLE_NAME = 'text' THEN 'text'::NODETYPE
        WHEN TG_TABLE_NAME = 'file' THEN 'file'::NODETYPE
        WHEN TG_TABLE_NAME = 'data_user' THEN 'user'::NODETYPE
      END
    )
    RETURNING id INTO NEW.node_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER text_trigger_insert_node
  BEFORE INSERT ON text
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_insert();

CREATE TRIGGER file_trigger_insert_node
  BEFORE INSERT ON file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_insert();

CREATE TRIGGER data_user_trigger_insert_node
  BEFORE INSERT ON data_user
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_insert();

-- Constraint: No node can exist without data
-- This is enforced through a deferred constraint check function
CREATE OR REPLACE FUNCTION check_node_has_data()
  RETURNS TRIGGER AS $$
BEGIN
  -- Check if the node has corresponding data
  IF NOT EXISTS (
    SELECT 1 FROM text WHERE node_id = NEW.id
    UNION ALL
    SELECT 1 FROM file WHERE node_id = NEW.id
    UNION ALL
    SELECT 1 FROM data_user WHERE node_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Node % must have corresponding data in text, file, or data_user table', NEW.id;
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
