# Data Type Template

This template provides the standardized pattern for adding new data_* tables to the qx-db schema.

## Template Usage

Replace `${TYPE}` with your data type name (e.g., 'memo', 'tag', 'link_meta').

```sql
-- 1. Add to NODETYPE enum
ALTER TYPE NODETYPE ADD VALUE '${TYPE}';

-- 2. Create table with standard pattern
CREATE TABLE data_${TYPE} (
  id SERIAL PRIMARY KEY,
  node_id INTEGER NOT NULL REFERENCES node (id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- ${TYPE}-specific fields here
  
  CONSTRAINT data_${TYPE}_node_unique UNIQUE (node_id)
);

-- 3. Standard indexes and triggers
CREATE INDEX idx_data_${TYPE}_node_id ON data_${TYPE} (node_id);

CREATE TRIGGER data_${TYPE}_trigger_updated_at
  BEFORE UPDATE ON data_${TYPE}
  FOR EACH ROW
  EXECUTE FUNCTION trigger_set_updated_at();

-- 4. Type-specific node creation trigger
CREATE OR REPLACE FUNCTION trigger_data_${TYPE}_insert()
  RETURNS TRIGGER AS $$
BEGIN
  IF NEW.node_id IS NULL THEN
    INSERT INTO node (type, creator_id) 
    VALUES ('${TYPE}'::NODETYPE, auth.uid())
    RETURNING id INTO NEW.node_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER data_${TYPE}_trigger_insert_node
  BEFORE INSERT ON data_${TYPE}
  FOR EACH ROW
  EXECUTE FUNCTION trigger_data_${TYPE}_insert();

-- 5. Standard RLS
ALTER TABLE data_${TYPE} ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Data follows node access" ON data_${TYPE}
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM accessible_nodes
      WHERE node_id = data_${TYPE}.node_id 
      AND user_id = auth.uid()
    )
  );
```

## Manual Updates Required

After adding the above SQL, you must manually update these two functions:

### 1. Update `check_node_has_data()` function
Add this line to the EXISTS check:
```sql
UNION ALL
SELECT 1 FROM data_${TYPE} WHERE node_id = NEW.id
```

## Naming Conventions

- **Table name**: `data_${TYPE}` (lowercase, underscore-separated)
- **Node type**: `${TYPE}` (matches table suffix)
- **Function name**: `trigger_data_${TYPE}_insert`
- **Trigger name**: `data_${TYPE}_trigger_insert_node`
- **Index prefix**: `idx_data_${TYPE}_`
- **Policy name**: `"Data follows node access"`

## Example: data_memo

```sql
-- data_memo specific fields
memo_type MEMOTYPE NOT NULL,
item_id INTEGER NOT NULL REFERENCES item (id) ON DELETE CASCADE,

-- Additional indexes
CREATE INDEX idx_data_memo_item_id ON data_memo (item_id);
CREATE INDEX idx_data_memo_type ON data_memo (memo_type);
```