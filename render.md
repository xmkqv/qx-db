- **Ephemeral tiles**: Temporary visual representations created for linked nodes without persistent tiles

```sql
-- Visual presentation types
CREATE TYPE ANCHOR AS ENUM ('lhs', 'rhs', 'flow');
CREATE TYPE VISUAL AS ENUM ('sec', 'doc', 'dir');
CREATE TYPE LAYOUT AS ENUM ('panel', 'slideshow');

CREATE TABLE tile (
    id SERIAL PRIMARY KEY,
    x REAL NOT NULL,
    y REAL NOT NULL,
    w REAL NOT NULL,
    h REAL NOT NULL,
    viewbox_x REAL NOT NULL,
    viewbox_y REAL NOT NULL,
    viewbox_zoom REAL NOT NULL,
    layout LAYOUT,
    visual VISUAL,
    anchor ANCHOR,
    motion INTEGER,
    active BOOLEAN DEFAULT FALSE,
    style JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```
