# Dual Lineage Tree Architecture

## Conventions

- **Naming**:
  - indexes: `index_<table>__<fields_separated_by__>`
  - table functions: 
    - `fn_<table>_<verb_object>`
    - `fn_<util|permission|sys>_<verb_object>`
    - `fn_<verb_object>`
  - triggers: `trigger_<table>_<event>_<verb_object>`
  - data tables: `data_<type>` (lowercase, underscore-separated)
  - migration files: 
    - `YYYYMMDDHHMMSS_<...>.sql` - generic pattern
    - `YYYYMMDDHHMMSS_<table>_init.sql` - initial table creation
    - `YYYYMMDDHHMMSS_<table>_<update>.sql` - changes to existing tables
  - policies: descriptive names in quotes

## File Tree

```
qx-db/
├── CLAUDE.md              # Project conventions and guidelines
├── architecture.md        # Primary source of truth for design
├── implementation.md      # Implementation notes and decisions
├── data_type.template.md  # Template for data table migrations
└── supabase/
    ├── config.toml
    ├── seed.sql           # (empty) Database seed data
    └── migrations/
        ├── 20250104000000_core_infrastructure.sql     # ENUMs, utilities
        ├── 20250104000001_node_access_init.sql       # Access control
        ├── 20250104000002_node_init.sql               # Node table
        ├── 20250104000003_tile_init.sql               # Tile table
        ├── 20250104000004_link_init.sql               # Link table
        ├── 20250104000005_item_init.sql               # Item table (dual lineage)
        ├── 20250104000006_data_text_init.sql          # Text data
        ├── 20250104000007_data_file_init.sql          # File data
        ├── 20250104000008_data_user_init.sql          # User data
        ├── 20250104000009_node_data_json_function.sql # JSON aggregation
        └── 20250104000011_user_workspace_roots_view.sql # User workspace view
```

### implementation.md: Structure

- Current state
- Desired Outcome
- Next Steps
- Issues and Concerns
