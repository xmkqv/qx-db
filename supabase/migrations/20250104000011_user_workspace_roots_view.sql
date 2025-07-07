-- Migration: User workspace roots materialized view

-- =============================================================================
-- Views
-- =============================================================================

-- Materialized view for user workspace roots (refreshed on user creation)
CREATE MATERIALIZED VIEW user_workspace_roots AS
SELECT 
  du.user_id,
  du.username,
  du.head_item_id,
  i.node_id as root_node_id,
  i.tile_id as root_tile_id
FROM data_user du
JOIN item i ON i.id = du.head_item_id
WHERE i.is_root;

CREATE INDEX index_user_workspace_roots__user_id ON user_workspace_roots(user_id);