# Flow: Adding a New Data Type

## Overview

Adding a new data type is a clean two-step process that leverages automatic trigger generation.

## Process Flow

```mermaid
graph TD
    Start([Start: Need New Data Type])
    Start --> Create[Create Migration File]
    
    Create --> Define[Define Pure Table Schema]
    Define --> |SQL| Table[data_[type] table]
    
    Table --> Push[Run db:push]
    Push --> Generate[Auto-generates Triggers]
    
    Generate --> Trigger[BEFORE INSERT trigger]
    Generate --> RLS[RLS Policies]
    Generate --> Function[Updates get_node_data]
    
    Trigger --> Complete[New Type Ready]
    RLS --> Complete
    Function --> Complete
    
    style Start fill:#805ad5,stroke:#fff,stroke-width:3px
    style Complete fill:#38a169,stroke:#fff,stroke-width:3px
```

## Step-by-Step

### Step 1: Create Migration with Pure Table Definition

```bash
supabase migration new add_data_video
```

### Step 2: Add ONLY the Table Definition

```sql
-- migrations/[timestamp]_add_data_video.sql
CREATE TABLE IF NOT EXISTS data_video (
    id SERIAL PRIMARY KEY,
    node_id INTEGER UNIQUE REFERENCES node(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    duration_seconds INTEGER,
    thumbnail_url TEXT
);
```

### Step 3: Push and Generate Everything Else

```bash
npm run db:push

# This automatically:
# - Creates the table
# - Generates triggers
# - Updates polymorphic functions
# - Makes it available in TypeScript
```

## What Gets Generated

```sql
-- Auto-generated in [timestamp]_generated_triggers.sql
CREATE OR REPLACE TRIGGER data_video_before_insert
BEFORE INSERT ON data_video
FOR EACH ROW
EXECUTE FUNCTION create_node_for_data('video');

ALTER TABLE data_video ENABLE ROW LEVEL SECURITY;

-- Type-specific policies
CREATE POLICY "video_read_policy" ON data_video
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "video_write_policy" ON data_video
    FOR ALL USING (auth.role() = 'authenticated');
```

## Important Notes

- **Never manually create triggers** - Let the generator handle it
- **Keep table definitions pure** - No triggers, functions, or policies in the initial migration
- **Follow naming convention** - Tables must be named `data_[type]`
- **One node_id per record** - The UNIQUE constraint ensures 1:1 relationship