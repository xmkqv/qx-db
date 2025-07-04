# Data Type Template

This template provides the standardized pattern for adding new data_* tables to the qx-db schema.

## Migration Structure

Each data type gets its own migration file: `YYYYMMDDHHMMSS_data_${TYPE}.sql`

## Template Usage

Replace `${TYPE}` with your data type name (e.g., 'text', 'file', 'user').

```sql
-- Migration: Data table - ${TYPE}

-- =============================================================================
-- ENUM EXTENSION
-- =============================================================================

-- Add '${TYPE}' to NodeType enum
ALTER TYPE NodeType ADD VALUE '${TYPE}';

-- =============================================================================
-- TABLE DEFINITION
-- =============================================================================

-- ${TYPE} data table
CREATE TABLE data_${TYPE} (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  
  -- ${TYPE}-specific fields here
  -- Example: content TEXT NOT NULL,
  -- Example: file_type FileType NOT NULL,
  -- Example: user_id UUID NOT NULL UNIQUE
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Standard indexes
CREATE INDEX index_data_${TYPE}__node_id ON data_${TYPE}(node_id);

-- Type-specific indexes
-- CREATE INDEX index_data_${TYPE}__specific_field ON data_${TYPE}(specific_field);

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Trigger to update node.updated_at when data changes
CREATE OR REPLACE FUNCTION fn_data_${TYPE}_update_node()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE node SET updated_at = NOW() WHERE id = NEW.node_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_${TYPE}_insert_update_update_node
  AFTER INSERT OR UPDATE ON data_${TYPE}
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_${TYPE}_update_node();

-- Optional: Auto-creation trigger (like data_user)
-- CREATE OR REPLACE FUNCTION fn_data_${TYPE}_auto_create()
-- RETURNS TRIGGER AS $$
-- BEGIN
--   -- Custom logic for auto-creation
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;
--
-- CREATE TRIGGER trigger_data_${TYPE}_insert_auto_create
--   BEFORE INSERT ON data_${TYPE}
--   FOR EACH ROW
--   EXECUTE FUNCTION fn_data_${TYPE}_auto_create();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on data table
ALTER TABLE data_${TYPE} ENABLE ROW LEVEL SECURITY;

-- Standard policy: delegate to node_permission
CREATE POLICY "Data follows node access" ON data_${TYPE}
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM node_permission
      WHERE node_id = data_${TYPE}.node_id 
      AND user_id = auth.uid()
    )
  );

-- Optional: Custom policies for special cases (like data_user)
-- CREATE POLICY "Users see own ${TYPE} data" ON data_${TYPE}
--   FOR SELECT
--   USING (
--     user_id = auth.uid() OR
--     EXISTS (
--       SELECT 1 FROM node_permission
--       WHERE node_id = data_${TYPE}.node_id 
--       AND user_id = auth.uid()
--     )
--   );
```

## Required Components

Every data migration MUST include:

1. **NodeType Extension**: `ALTER TYPE NodeType ADD VALUE '${TYPE}';`
2. **Table Definition**: With `node_id` foreign key
3. **Standard Index**: `index_data_${TYPE}__node_id`
4. **Update Trigger**: Updates parent node timestamp
5. **RLS Policies**: At minimum, delegate to `node_permission`

## Optional Components

Depending on the data type:

1. **Type-specific indexes**: For common query patterns
2. **Auto-creation triggers**: For complex initialization (like user workspaces)
3. **Custom RLS policies**: For special access patterns
4. **Full-text search**: GIN indexes for text content
5. **Additional ENUMs**: Type-specific enumerations

## Naming Conventions

- **Migration**: `YYYYMMDDHHMMSS_data_${TYPE}.sql`
- **Table**: `data_${TYPE}` (lowercase, underscore-separated)
- **Functions**: `fn_data_${TYPE}_<verb_object>`
- **Triggers**: `trigger_data_${TYPE}_<event>_<verb_object>`
- **Indexes**: `index_data_${TYPE}__<fields_separated_by__>`
- **Policies**: Descriptive names in quotes

## Example: data_text

```sql
-- Migration: Data table - text

-- Add 'text' to NodeType enum
ALTER TYPE NodeType ADD VALUE 'text';

-- Text data table
CREATE TABLE data_text (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL UNIQUE REFERENCES node(id) ON DELETE CASCADE,
  content TEXT NOT NULL
);

-- Standard indexes
CREATE INDEX index_data_text__node_id ON data_text(node_id);

-- Full-text search index
CREATE INDEX index_data_text__content_fts ON data_text USING gin(to_tsvector('english', content));

-- Trigger to update node.updated_at when data changes
CREATE OR REPLACE FUNCTION fn_data_text_update_node()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE node SET updated_at = NOW() WHERE id = NEW.node_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_data_text_insert_update_update_node
  AFTER INSERT OR UPDATE ON data_text
  FOR EACH ROW
  EXECUTE FUNCTION fn_data_text_update_node();

-- Enable RLS
ALTER TABLE data_text ENABLE ROW LEVEL SECURITY;

-- Standard RLS policy
CREATE POLICY "Data follows node access" ON data_text
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM node_permission
      WHERE node_id = data_text.node_id 
      AND user_id = auth.uid()
    )
  );
```

## Migration Dependencies

Data migrations depend on:
1. `20250104000000_core_infrastructure.sql` - For utility functions
2. `20250104000001_node.sql` - For node table and NodeType enum
3. `20250104000005_node_permission.sql` - For node_permission view

Data migrations are independent of each other and can be created in any order.