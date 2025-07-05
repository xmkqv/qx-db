-- Migration: Core infrastructure and utilities

-- =============================================================================
-- SHARED UTILITY FUNCTIONS
-- =============================================================================

-- Standard updated_at trigger function
CREATE OR REPLACE FUNCTION fn_trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- DOMAIN TYPES
-- =============================================================================

-- Domain types for better type safety and self-documenting code
CREATE DOMAIN positive_id AS INTEGER
  CHECK (VALUE > 0);

CREATE DOMAIN coordinate AS INTEGER
  CHECK (VALUE >= -2147483648 AND VALUE <= 2147483647);

CREATE DOMAIN dimension AS INTEGER  
  CHECK (VALUE > 0);

-- =============================================================================
-- UTILITY FUNCTIONS FOR ADVANCED FEATURES
-- =============================================================================

-- Function to check if array contains any of the given values
CREATE OR REPLACE FUNCTION fn_util_array_contains_any(arr anyarray, vals anyarray)
RETURNS BOOLEAN AS $$
  SELECT arr && vals;
$$ LANGUAGE sql IMMUTABLE;

-- Function to get the highest permission from an array
CREATE OR REPLACE FUNCTION fn_util_highest_permission(perms text[])
RETURNS text AS $$
  SELECT CASE
    WHEN 'admin' = ANY(perms) THEN 'admin'
    WHEN 'edit' = ANY(perms) THEN 'edit'
    WHEN 'view' = ANY(perms) THEN 'view'
    ELSE NULL
  END;
$$ LANGUAGE sql IMMUTABLE;

-- =============================================================================
-- JSON AGGREGATION UTILITIES
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