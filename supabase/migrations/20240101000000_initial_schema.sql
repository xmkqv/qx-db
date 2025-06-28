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
  'text'
);

CREATE TABLE node (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  type NODETYPE NOT NULL
);

CREATE INDEX node_index_type ON node (type);

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
  ascn_id INTEGER REFERENCES item (id) ON DELETE CASCADE,
  prev_id INTEGER REFERENCES item (id) ON DELETE SET NULL,
  tile_id INTEGER NOT NULL REFERENCES tile (id) ON DELETE CASCADE,
  CHECK (id != ascn_id),
  CHECK (id != prev_id)
);

CREATE INDEX item_index_ascn_id ON item (ascn_id);

CREATE INDEX item_index_prev_id ON item (prev_id);

CREATE INDEX item_index_node_id ON item (node_id);

CREATE INDEX item_index_tile_id ON item (tile_id);

CREATE INDEX item_index_root ON item (ascn_id, prev_id)
WHERE
  ascn_id IS NULL AND prev_id IS NULL;

CREATE INDEX item_index_peers ON item (ascn_id, prev_id);

CREATE TRIGGER item_trigger_updated_at
  BEFORE UPDATE ON item
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

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
  uri TEXT NOT NULL,
);

CREATE TRIGGER file_trigger_updated_at
  BEFORE UPDATE ON file
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at ();

CREATE INDEX idx_file_node_id ON file (node_id);

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

CREATE INDEX idx_text_node_id ON TEXT(node_id);

-- Add full-text search index on text content
CREATE INDEX idx_text_content_fts ON text USING gin
  (TO_TSVECTOR('english', content));
