-- Migration: Tile table

-- =============================================================================
-- TABLE DEFINITION
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
-- INDEXES
-- =============================================================================

-- Indexes for tile table
CREATE INDEX index_tile__x__y ON tile(x, y);
-- Index for spatial queries using generated columns
CREATE INDEX index_tile__bounds ON tile(x, y, x_max, y_max);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on tile table
ALTER TABLE tile ENABLE ROW LEVEL SECURITY;

-- Tile table policies
CREATE POLICY "tile_select_policy" ON tile
  FOR SELECT
  USING (
    id IN (
      SELECT tile_id FROM item 
      WHERE fn_item_check_access(id, auth.uid(), 'view')
      AND tile_id IS NOT NULL
    )
  );

CREATE POLICY "tile_insert_policy" ON tile
  FOR INSERT
  WITH CHECK (TRUE);  -- Tiles are validated when associated with items

CREATE POLICY "tile_update_policy" ON tile
  FOR UPDATE
  USING (
    id IN (
      SELECT tile_id FROM item 
      WHERE fn_item_check_access(id, auth.uid(), 'edit')
      AND tile_id IS NOT NULL
    )
  );

CREATE POLICY "tile_delete_policy" ON tile
  FOR DELETE
  USING (
    id IN (
      SELECT tile_id FROM item 
      WHERE fn_item_check_access(id, auth.uid(), 'admin')
      AND tile_id IS NOT NULL
    )
  );