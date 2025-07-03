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
-- NODETYPE enum will be extended by data_* migrations
CREATE TYPE NODETYPE AS ENUM ();

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
  viewbox_x REAL NOT NULL,
  viewbox_y REAL NOT NULL,
  viewbox_zoom REAL NOT NULL,
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

-- Data tables and their triggers will be added by separate migrations


--
-- Row Level Security Policies
--

-- Enable RLS on all tables
ALTER TABLE node ENABLE ROW LEVEL SECURITY;
ALTER TABLE node_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE link ENABLE ROW LEVEL SECURITY;
ALTER TABLE item ENABLE ROW LEVEL SECURITY;
ALTER TABLE tile ENABLE ROW LEVEL SECURITY;
-- Data table RLS will be enabled by their respective migrations

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

-- Data table policies will be created by their respective migrations

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
