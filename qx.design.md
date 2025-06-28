# qx Design

**One graph, infinite views**

## Overview

- Data = DataText | DataFile | ... (`data_<type>`)
- Data interface & structure is introduced by proxy polymorphism
- Node:
  - Discriminator: `type`
  - Unified interface to data
  - Separates metadata (Node) from data (Data[type])
  - Referential integrity is maintained by **not null reverse ownership** (otherwise could have dangling data if no node -> data)
- Node is read-only ie has get but no add/set/del
  - add: [triggers by data insert](#trigger-data-insert)
  - del: cascade delete via data table
  - set: updates are triggers, eg update timestamps (or later update embeddings)
- nbrs (neighbors) = linked nodes ∪ descendant items
  - Link: directed edge between two nodes (src [1>1] dst), atomic semantic relationships
  - Item: hierarchical relationship between nodes, molecular hierarchical relationships
    - item.ascn_id [n>1|0] ascendent
    - item.prev_id [1>1|0] previous: nullable, so root === ascn_id = NULL & prev_id = NULL
- Tile: a rendered node
  - [tile.item_id](#item-tile-non-reverse-ownership) [1>1] item not null [unique](#item-tile-uniqueness)
  - We can create tiles in the client without a corresponding item, for src/dst render, but this is not stored in the database, meaning we maintain a separate client-side store for ephemeral tiles

## Fundamental Schema

```sql
CREATE TABLE node (
    id SERIAL PRIMARY KEY,
    type TEXT NOT NULL
);


CREATE TABLE data_text (
    id SERIAL PRIMARY KEY,
    node_id INTEGER UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    content TEXT NOT NULL
);

CREATE TABLE data_file (
    id SERIAL PRIMARY KEY,
    node_id INTEGER UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    uri TEXT NOT NULL
);
-- ... etc

CREATE TABLE link (
    id SERIAL PRIMARY KEY,
    src_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    dst_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    UNIQUE(src_id, dst_id)
);

CREATE TABLE tile (
    id SERIAL PRIMARY KEY,
    --... qx.render.md
);

CREATE TABLE item (
    id SERIAL PRIMARY KEY,
    node_id INTEGER NOT NULL REFERENCES node(id) ON DELETE CASCADE,
    ascn_id INTEGER REFERENCES item(id) ON DELETE CASCADE,
    prev_id INTEGER REFERENCES item(id) ON DELETE SET NULL,
    tile_id INTEGER NOT NULL REFERENCES tile(id) ON DELETE CASCADE,
    CHECK (id != ascn_id),
    CHECK (id != prev_id)
);

-- example query
CREATE OR REPLACE FUNCTION get_descs (ascn_id INTEGER)
  RETURNS SETOF item
  AS $$
BEGIN
  RETURN QUERY
  SELECT
    *
  FROM
    item
  WHERE
    item.ascn_id = get_descs.ascn_id
  ORDER BY
    prev_id NULLS FIRST, id;
END;
$$
LANGUAGE plpgsql;

-- ... etc
```

## Triggers

### Trigger: Data Insert

```sql
CREATE OR REPLACE FUNCTION create_node_for_data()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.node_id IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext(TG_TABLE_NAME || TG_OP));
        INSERT INTO node (type)
        VALUES (TG_ARGV[0])
        RETURNING id INTO NEW.node_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Applied to each data table:
CREATE TRIGGER data_text_before_insert
BEFORE INSERT ON data_text
FOR EACH ROW
EXECUTE FUNCTION create_node_for_data('text');
```

### Codegen

Generates for each `data_<type>` table:

- BEFORE INSERT trigger → `create_node_for_data(type)`
- RLS policies (public vs authenticated)
- Retrieval function `get_<type>(node_id)`

```typescript
// scripts/generate-triggers.ts
for await (const { tableName, typeName } of getDataTables(client)) {
  migrations.push(`
CREATE TRIGGER ${tableName}_before_insert
BEFORE INSERT ON ${tableName}
FOR EACH ROW
EXECUTE FUNCTION create_node_for_data('${typeName}');

ALTER TABLE ${tableName} ENABLE ROW LEVEL SECURITY;

CREATE POLICY "${typeName}_read" ON ${tableName}
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "${typeName}_write" ON ${tableName}
  FOR ALL USING (auth.role() = 'authenticated');
`)
}
```

## Later @lock

- Race condition prevention (advisory locks)
- Timestamps (created_at, updated_at)
- Embeddings

## Exclusions

- @exclude: INHERITS for polymorphism - FK constraints break
- @exclude: Table partitioning - overcomplex, breaks FKs
- @exclude: JSONB storage - loses schema benefits
- @exclude: Array composite types - poor query performance
- @exclude: Materialized views - stale data issues
- @exclude: NOTIFY/LISTEN - Supabase Realtime handles this
- @exclude: Custom types/domains - client compatibility
- @exclude: UUID PKs - integers are simpler

### Item-Tile Uniqueness

- Could be not unique (eg multiple items point to the same tile)
  - Tiles are already a rendered representation of a node, which has Item [n>1] Node, so it's **almost** redundant

### Item-Tile non-Reverse Ownership

**Proof by contradiction:**

- Item has a foreign key to Tile, but Tile does not have a foreign key to Item (this would be normalization which we avoid)
- However, referential integrity is broken as a tile does not need a an item to exist
- However, we need this to be the case to allow ephemeral tiles (eg for links)
- However, these don't actually need to exist in the database
- So, reverse ownership gives referential integrity and still allows for ephemeral tiles
