-- Migration: Item table with dual lineage

-- =============================================================================
-- Table definition
-- =============================================================================

-- Enhanced item table with ascn_id for dual lineage
CREATE TABLE item (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
  ascn_id INTEGER REFERENCES item(id) ON DELETE CASCADE,  -- Ascendant
  desc_id INTEGER REFERENCES item(id),  -- Head of branch (will add trigger)
  next_id INTEGER REFERENCES item(id),  -- Next peer (will add trigger)
  tile_id INTEGER REFERENCES tile(id) ON DELETE SET NULL,  -- NULL = no visual yet
  is_root BOOLEAN GENERATED ALWAYS AS (ascn_id IS NULL) STORED,  -- Computed root indicator
  CHECK (id != ascn_id AND id != desc_id AND id != next_id)  -- No self-reference
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX index_item__ascn_id ON item(ascn_id);
CREATE INDEX index_item__desc_id ON item(desc_id);
CREATE INDEX index_item__next_id ON item(next_id);
CREATE INDEX index_item__node_id ON item(node_id);
CREATE INDEX index_item__root ON item(id) WHERE ascn_id IS NULL;

CREATE INDEX index_item__id__ascn_id ON item(id, ascn_id);
CREATE INDEX index_item__desc_id_not_null ON item(id) WHERE desc_id IS NOT NULL;

-- =============================================================================
-- Functions and triggers
-- =============================================================================

-- Function to check for cycles in ascn_id chain
CREATE OR REPLACE FUNCTION fn_item_check_ascn_cycle()
RETURNS TRIGGER AS $$
DECLARE
  current_id INTEGER;
  visited_ids INTEGER[];
BEGIN
  -- Only check if ascn_id is being set
  IF NEW.ascn_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  current_id := NEW.ascn_id;
  visited_ids := ARRAY[NEW.id];
  
  -- Follow the chain up to detect cycles
  WHILE current_id IS NOT NULL LOOP
    -- Check if we've seen this ID before
    IF current_id = ANY(visited_ids) THEN
      RAISE EXCEPTION 'Circular reference detected in ascn_id chain: % -> %', 
        array_to_string(visited_ids || current_id, ' -> '), current_id;
    END IF;
    
    -- Add to visited list
    visited_ids := visited_ids || current_id;
    
    -- Get next in chain
    SELECT ascn_id INTO current_id 
    FROM item 
    WHERE id = current_id;
    
    -- Safety limit to prevent infinite loops in case of data corruption
    IF array_length(visited_ids, 1) > 100 THEN
      RAISE EXCEPTION 'ascn_id chain too deep (>100 levels)';
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle complex item deletion per the deletion matrix
CREATE OR REPLACE FUNCTION fn_item_handle_deletion()
RETURNS TRIGGER AS $$
DECLARE
  is_root BOOLEAN;
  has_native_desc BOOLEAN;
  acts_as_head BOOLEAN;
  has_peers BOOLEAN;
  predecessor_id INTEGER;
BEGIN
  -- Determine item characteristics
  is_root := OLD.ascn_id IS NULL;
  
  -- Check for native descendants
  SELECT EXISTS(
    SELECT 1 FROM item WHERE ascn_id = OLD.id
  ) INTO has_native_desc;
  
  -- Check if acts as head
  SELECT EXISTS(
    SELECT 1 FROM item WHERE desc_id = OLD.id
  ) INTO acts_as_head;
  
  -- Check for peers and find predecessor
  SELECT EXISTS(
    SELECT 1 FROM item WHERE desc_id = OLD.desc_id AND next_id = OLD.id
  ) INTO has_peers;
  
  IF has_peers THEN
    SELECT id INTO predecessor_id 
    FROM item 
    WHERE desc_id = OLD.desc_id AND next_id = OLD.id
    LIMIT 1;
  END IF;
  
  -- Apply deletion matrix logic
  IF is_root THEN
    IF has_native_desc THEN
      -- R1: Cascade delete (handled by FK CASCADE)
    ELSIF acts_as_head THEN
      -- R2: Head repoint
      UPDATE item SET desc_id = NULL WHERE desc_id = OLD.id;
    END IF;
    -- R3: Simple delete
  ELSE
    -- Non-root cases
    IF has_native_desc THEN
      IF NOT acts_as_head AND has_peers THEN
        -- N3: Native cascade + splice
        UPDATE item SET next_id = OLD.next_id WHERE id = predecessor_id;
      END IF;
      -- N1, N2: Native cascade handled by FK
    ELSIF acts_as_head THEN
      -- H1, H2: Check if flux item
      IF EXISTS(
        SELECT 1 FROM item stem 
        WHERE stem.desc_id = OLD.id AND stem.id != OLD.ascn_id
      ) THEN
        RAISE EXCEPTION 'Cannot delete flux item % (acts as head for another tree)', OLD.id;
      END IF;
      
      -- Update stems pointing to this head
      UPDATE item SET desc_id = OLD.next_id WHERE desc_id = OLD.id;
      
      IF has_peers THEN
        -- H2: Head repoint + splice
        UPDATE item SET next_id = OLD.next_id WHERE id = predecessor_id;
      END IF;
    ELSIF has_peers THEN
      -- P1: Peer splice
      UPDATE item SET next_id = OLD.next_id WHERE id = predecessor_id;
    END IF;
    -- T1: Terminal delete
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Constraint to ensure flux items are always heads (no incoming next_id)
CREATE OR REPLACE FUNCTION fn_item_check_flux_constraint()
RETURNS TRIGGER AS $$
BEGIN
  -- If this item is referenced by desc_id and has different ascn_id (flux condition)
  IF EXISTS(
    SELECT 1 FROM item stem 
    WHERE stem.desc_id = NEW.id AND stem.id != NEW.ascn_id
  ) THEN
    -- Ensure no item points to this as next_id
    IF EXISTS(SELECT 1 FROM item WHERE next_id = NEW.id) THEN
      RAISE EXCEPTION 'Flux items must be heads (cannot have incoming next_id): item %', NEW.id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add deletion triggers for desc_id and next_id
CREATE TRIGGER trigger_item_delete_handle_deletion
  BEFORE DELETE ON item
  FOR EACH ROW
  EXECUTE FUNCTION fn_item_handle_deletion();

-- Add cycle detection trigger
CREATE TRIGGER trigger_item_insert_update_check_cycle
  BEFORE INSERT OR UPDATE OF ascn_id ON item
  FOR EACH ROW
  EXECUTE FUNCTION fn_item_check_ascn_cycle();

CREATE CONSTRAINT TRIGGER trigger_item_insert_update_check_flux
  AFTER INSERT OR UPDATE ON item
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION fn_item_check_flux_constraint();

-- =============================================================================
-- Item helper functions
-- =============================================================================

-- Helper function to add a descendant to an item (handles ascn_id assignment)
CREATE OR REPLACE FUNCTION fn_item_add_desc(
  p_stem_id INTEGER,
  p_node_id INTEGER,
  p_tile_id INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
  new_item_id INTEGER;
  stem_desc_id INTEGER;
BEGIN
  -- Get current desc_id of stem
  SELECT desc_id INTO stem_desc_id FROM item WHERE id = p_stem_id;
  
  -- Create new item with proper ascn_id (native growth)
  INSERT INTO item (node_id, ascn_id, next_id, tile_id)
  VALUES (p_node_id, p_stem_id, stem_desc_id, p_tile_id)
  RETURNING id INTO new_item_id;
  
  -- Update stem to point to new item
  UPDATE item SET desc_id = new_item_id WHERE id = p_stem_id;
  
  RETURN new_item_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function to add a peer to an item
CREATE OR REPLACE FUNCTION fn_item_add_next(
  p_current_id INTEGER,
  p_node_id INTEGER,
  p_tile_id INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
  new_item_id INTEGER;
  current_item RECORD;
BEGIN
  -- Get current item details
  SELECT * INTO current_item FROM item WHERE id = p_current_id;
  
  IF current_item IS NULL THEN
    RAISE EXCEPTION 'Item % not found', p_current_id;
  END IF;
  
  -- Create new item with same ascn_id as current (peer relationship)
  INSERT INTO item (node_id, ascn_id, next_id, tile_id)
  VALUES (p_node_id, current_item.ascn_id, current_item.next_id, p_tile_id)
  RETURNING id INTO new_item_id;
  
  -- Update current item to point to new peer
  UPDATE item SET next_id = new_item_id WHERE id = p_current_id;
  
  RETURN new_item_id;
END;
$$ LANGUAGE plpgsql;

-- Function to compose a tree (creates flux)
CREATE OR REPLACE FUNCTION fn_item_compose(
  p_stem_id INTEGER,
  p_target_item_id INTEGER
) RETURNS VOID AS $$
DECLARE
  stem_record RECORD;
  target_record RECORD;
BEGIN
  -- Get stem and target details
  SELECT * INTO stem_record FROM item WHERE id = p_stem_id;
  SELECT * INTO target_record FROM item WHERE id = p_target_item_id;
  
  IF stem_record IS NULL THEN
    RAISE EXCEPTION 'Stem item % not found', p_stem_id;
  END IF;
  
  IF target_record IS NULL THEN
    RAISE EXCEPTION 'Target item % not found', p_target_item_id;
  END IF;
  
  -- Check if target already has incoming next_id (flux constraint)
  IF EXISTS(SELECT 1 FROM item WHERE next_id = p_target_item_id) THEN
    RAISE EXCEPTION 'Target item % cannot be composed (has incoming next_id)', p_target_item_id;
  END IF;
  
  -- Set desc_id to create composition (flux if ascn_id differs)
  UPDATE item SET desc_id = p_target_item_id WHERE id = p_stem_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get branch (all descendants of an item, native and flux) using advanced CTE
CREATE OR REPLACE FUNCTION fn_item_get_branch(p_item_id INTEGER)
RETURNS TABLE(
  item_id INTEGER,
  node_id INTEGER,
  is_native BOOLEAN,
  is_flux BOOLEAN,
  depth INTEGER,
  path INTEGER[]
) AS $$
WITH RECURSIVE descendants AS (
  -- Base case: direct descendants
  SELECT 
    i.id as item_id,
    i.node_id,
    i.ascn_id = p_item_id as is_native,
    i.ascn_id != p_item_id as is_flux,
    1 as depth,
    ARRAY[p_item_id, i.id] as path,
    false as cycle
  FROM item i
  WHERE i.ascn_id = p_item_id OR i.id = (SELECT desc_id FROM item WHERE id = p_item_id)
  
  UNION ALL
  
  -- Recursive case: traverse both desc_id and next_id
  SELECT DISTINCT
    i.id as item_id,
    i.node_id,
    i.ascn_id = p_item_id as is_native,
    i.ascn_id != p_item_id as is_flux,
    d.depth + 1,
    d.path || i.id,
    i.id = ANY(d.path) as cycle
  FROM descendants d
  JOIN item parent ON parent.id = d.item_id
  JOIN item i ON (i.ascn_id = parent.id OR i.id = parent.desc_id)
  WHERE NOT d.cycle AND d.depth < 20
)
SELECT DISTINCT ON (item_id) 
  item_id, 
  node_id, 
  is_native, 
  is_flux, 
  depth,
  path
FROM descendants 
WHERE NOT cycle
ORDER BY item_id, depth;
$$ LANGUAGE sql;

-- Function to detect if an item is in a flux condition
CREATE OR REPLACE FUNCTION fn_item_in_flux(p_item_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
  result BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 
    FROM item descendant
    JOIN item stem ON stem.desc_id = descendant.id
    WHERE descendant.id = p_item_id 
    AND stem.id != descendant.ascn_id
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- Row level security
-- =============================================================================

-- Enable RLS on item table
ALTER TABLE item ENABLE ROW LEVEL SECURITY;

-- Item table policies
CREATE POLICY "Users can view items they have access to" ON item
  FOR SELECT
  USING (user_has_node_access(node_id, 4));  -- VIEW permission

CREATE POLICY "Users can insert items they can edit" ON item
  FOR INSERT
  WITH CHECK (user_has_node_access(node_id, 2));  -- EDIT permission

CREATE POLICY "Users can update items they can edit" ON item
  FOR UPDATE
  USING (user_has_node_access(node_id, 2))  -- EDIT permission
  WITH CHECK (user_has_node_access(node_id, 2));

CREATE POLICY "Users can delete items they admin" ON item
  FOR DELETE
  USING (user_has_node_access(node_id, 1));  -- ADMIN permission

-- =============================================================================
-- Enhanced tile policies now that item table exists
-- =============================================================================

-- Drop basic tile policies
DROP POLICY "tile_select_policy" ON tile;
DROP POLICY "tile_update_policy" ON tile;
DROP POLICY "tile_delete_policy" ON tile;

-- Create enhanced policies that check permissions through items
CREATE POLICY "tile_select_policy" ON tile
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 4)  -- VIEW permission
    )
  );

CREATE POLICY "tile_update_policy" ON tile
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

CREATE POLICY "tile_delete_policy" ON tile
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM item i
      WHERE i.tile_id = tile.id
      AND user_has_node_access(i.node_id, 1)  -- ADMIN permission
    )
  );