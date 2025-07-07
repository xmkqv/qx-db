-- Migration: Node data JSON aggregation function

-- =============================================================================
-- JSON aggregation function (depends on node and data tables)
-- =============================================================================

-- Function to safely aggregate node data with type information
CREATE OR REPLACE FUNCTION fn_node_data_json(p_node_id INTEGER)
RETURNS JSONB AS $$
  SELECT jsonb_build_object(
    'node_id', n.id,
    'type', n.type,
    'created_at', n.created_at,
    'updated_at', n.updated_at,
    'data', CASE n.type
      WHEN 'text' THEN (SELECT row_to_json(t.*) FROM data_text t WHERE t.node_id = n.id)
      WHEN 'file' THEN (SELECT row_to_json(f.*) FROM data_file f WHERE f.node_id = n.id)
      WHEN 'user' THEN (SELECT row_to_json(u.*) FROM data_user u WHERE u.node_id = n.id)
      ELSE NULL
    END
  )
  FROM node n
  WHERE n.id = p_node_id;
$$ LANGUAGE sql STABLE;