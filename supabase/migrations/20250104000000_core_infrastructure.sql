-- Migration: Core infrastructure and utilities

-- =============================================================================
-- Shared utility functions
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
-- Enums
-- =============================================================================

-- Note: NodeType moved to node_init.sql
-- Note: FileType moved to data_file_init.sql

-- =============================================================================
-- Domain types
-- =============================================================================

-- Domain types for better type safety and self-documenting code
CREATE DOMAIN positive_id AS INTEGER
  CHECK (VALUE > 0);

CREATE DOMAIN coordinate AS INTEGER
  CHECK (VALUE >= -2147483648 AND VALUE <= 2147483647);

CREATE DOMAIN dimension AS INTEGER  
  CHECK (VALUE > 0);

-- =============================================================================
-- Utility functions for advanced features
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
-- JSON aggregation utilities
-- =============================================================================

-- Note: fn_node_data_json function moved to a later migration after all tables are created