-- Migration: Tile table

-- =============================================================================
-- Table definition
-- =============================================================================

-- Tile table with spatial constraints
CREATE TABLE tile (
  id SERIAL PRIMARY KEY,
  x coordinate NOT NULL,  -- Using domain type
  y coordinate NOT NULL,
  w dimension NOT NULL,   -- Using domain type
  h dimension NOT NULL,
  viewbox_x coordinate NOT NULL DEFAULT 0,
  viewbox_y coordinate NOT NULL DEFAULT 0,
  viewbox_zoom REAL NOT NULL DEFAULT 1.0 CHECK (viewbox_zoom > 0),
  -- Generated columns for bounds
  x_max coordinate GENERATED ALWAYS AS (x + w - 1) STORED,
  y_max coordinate GENERATED ALWAYS AS (y + h - 1) STORED
);

-- =============================================================================
-- Indexes
-- =============================================================================
CREATE INDEX index_tile__x__y ON tile(x, y);
-- Index for spatial queries using generated columns
CREATE INDEX index_tile__bounds ON tile(x, y, x_max, y_max);

-- =============================================================================
-- Row level security
-- =============================================================================

-- Enable RLS on tile table
ALTER TABLE tile ENABLE ROW LEVEL SECURITY;

-- Tile policies - tiles are managed through items that reference them
-- Users can view tiles referenced by items they have access to
CREATE POLICY "Users can view tiles used by accessible items" ON tile
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 4)  -- VIEW permission
    )
  );

-- Users can create tiles when they have edit access to use them
CREATE POLICY "Users can create tiles for their items" ON tile
  FOR INSERT
  WITH CHECK (TRUE);  -- Actual permission check happens when associating with item

-- Users can update tiles used by items they can edit
CREATE POLICY "Users can update tiles they have edit access to" ON tile
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 2)  -- EDIT permission
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 2)  -- EDIT permission
    )
  );

-- Users can delete tiles used by items they can admin
CREATE POLICY "Users can delete tiles they have admin access to" ON tile
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 1)  -- ADMIN permission
    )
  );