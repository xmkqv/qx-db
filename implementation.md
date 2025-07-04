# Implementation Notes

This document tracks missing information, decisions, and concerns encountered during my implementation of the Dual Lineage Tree Architecture.

## Role Clarification
I am the implementer responsible for creating the database migrations based on the architecture specification. My role includes:
- Interpreting the architecture document
- Making implementation decisions where details are missing
- Creating functional migrations that realize the design
- Documenting gaps and decisions made

## Architecture Gaps and Implementation Decisions

### 1. Trigger Functions ✅
- **Gap**: Architecture specifies ON DELETE TRIGGER but doesn't provide implementations
- **Decision**: Implemented `fn_item_handle_deletion()` based on deletion matrix
- **Status**: Complete - handles all cases R1-R3, N1-N3, H1-H2, P1, T1

### 2. Tile Table Specification ✅
- **Gap**: Architecture shows INTEGER coordinates, no mention of viewbox fields
- **Decision**: Implemented as specified with INTEGER coordinates and viewbox fields
- **Status**: Complete - matches architecture

### 3. Updated_at Trigger ✅
- **Gap**: Referenced but not defined in architecture
- **Decision**: Implemented standard `fn_trigger_set_updated_at()`
- **Status**: Complete - applied to all tables needing timestamps

### 4. Auth System ✅
- **Gap**: Architecture references auth.users without specifying provider
- **Decision**: Using Supabase auth schema
- **Status**: Complete - all references use auth.uid() and auth.users

### 5. Node Permission View ✅
- **Gap**: Not defined in architecture but critical for permissions
- **Decision**: Created node_permission view combining creator and explicit grants
- **Status**: Complete - centralizes permission logic
- **Update**: Renamed from accessible_nodes to node_permission for clarity

### 6. Helper Functions ✅
- **Gap**: Architecture mentions but doesn't define fn_item_add_desc/next
- **Decision**: Implemented all helper functions with proper ascn_id handling
- **Status**: Complete - includes fn_head_item_compose, get_branch, item_in_flux

### 7. Cycle Detection ✅
- **Gap**: Mentioned but not implemented
- **Decision**: Created `fn_item_check_ascn_cycle()` trigger
- **Status**: Complete - prevents circular ascn_id chains

### 8. FileType Enum ✅
- **Gap**: Architecture now shows only 'png'
- **Decision**: Matched architecture exactly
- **Status**: Complete - FileType has single 'png' value

### 9. Permission Model ✅
- **Gap**: Architecture now clearly states least permissive wins
- **Decision**: Implemented dual-lineage checks for flux items
- **Status**: Complete - both lineages must grant access

### 10. NodeType Enum Management ✅
- **Gap**: Not clear where NodeType values should be defined
- **Decision**: Empty enum in core, extended by each data table migration
- **Status**: Complete - colocated with data tables

## Additional Concerns

### 1. Migration Order Dependencies
- ENUMs must be created before they're used
- Node table must exist before any references to it
- Item table self-references require careful constraint handling

### 2. Data Integrity During Migration
- Since this is a fresh start with no data import, we can use stricter constraints
- Can enforce all foreign keys immediately

### 3. Performance Considerations
- Missing indexes from architecture:
  - Composite indexes for common query patterns
  - Partial indexes for WHERE clauses
- Will add based on documented query patterns

### 4. RLS Policy Complexity
- Flux-aware permissions require complex RLS policies
- Starting with simpler policies, can enhance based on actual usage

## Implementation Approach

### 1. Migration Structure (Supabase Format) - FINAL
Properly colocated with one migration per table/concept:
- `20250104000000_core_infrastructure.sql` - ENUMs and utility functions only
- `20250104000001_node.sql` - Node table with indexes, triggers, RLS policies
- `20250104000002_tile.sql` - Tile table with indexes, RLS policies
- `20250104000003_link.sql` - Link table with indexes, RLS policies
- `20250104000004_item.sql` - Item table with complete implementation:
  - Table definition + indexes
  - All item functions (helpers, traversal, flux detection, access checking)
  - Triggers (deletion matrix, cycle detection, flux constraints)
  - RLS policies
- `20250104000005_node_permission.sql` - Node permissions with complete implementation:
  - node_access table + indexes
  - node_permission view (combines explicit grants and creator access)
  - Flux-aware permission functions
  - RLS policies
  - Link permissions derived from src node (no separate table)
- `20250104000006_data_text.sql` - Text data table following template
- `20250104000007_data_file.sql` - File data table following template
- `20250104000008_data_user.sql` - User data table with workspace creation

**Design Principles**: 
1. One migration per table/concept for maximum maintainability
2. Each migration is completely self-contained
3. Functions/triggers colocated with their primary tables
4. Data tables follow standardized template pattern
5. Trigger naming: `trigger_<table>_<event>_<verb_object>`

### 2. Naming Conventions (Per Architecture)
- **Tables**: lowercase_underscore
- **Indexes**: `index_<table>__<fields_separated_by__>`
- **Functions**: `fn_<table>_<verb_object>`
- **Triggers**: `trigger_<table>_<event>_<verb_object>`
- **Policies**: Descriptive names in quotes

### 3. Invariant Enforcement
- Database constraints prevent invalid states
- Triggers enforce business rules (deletion matrix, cycles)
- RLS policies secure at database level
- Minimal application logic needed

### 4. Testing Philosophy
- Invariant-based design minimizes testing needs
- Focus on dual lineage operations
- Verify flux permission boundaries
- Test user workspace creation

## Key Implementation Details

### 1. Dual Lineage Implementation
- `ascn_id` tracks ascendant lineage (where item came from)
- `desc_id` tracks stem lineage (what item points to)
- Flux detection: `stem.id != descendant.ascn_id`
- Native growth: `new_item.ascn_id = stem.id`

### 2. Deletion Trigger Implementation
- **Trigger**: `item_trigger_handle_deletion` (BEFORE DELETE)
- **Function**: `fn_item_handle_deletion()` based on deletion matrix
- Handles all cases: R1-R3, N1-N3, H1-H2, P1, T1
- Prevents deletion of flux items per P3
- Automatic peer splicing and head repointing

### 3. Access Control Implementation
- `node_permission` view combines explicit grants and creator access
- `fn_node_check_access_flux()` handles flux-aware permissions
- Least permissive wins at flux boundaries
- Link permissions derived from src node permissions

### 4. Data Table Pattern
- Each data table follows template structure
- Node type validation ensures type matches data table
- Automatic node.updated_at updates via triggers
- RLS policies delegate to node_permission view

### 5. User Workspace Implementation
- `data_user.head_item_id` provides entry point
- Automatic root item creation for new users
- Root item has `ascn_id = NULL` per architecture

### 6. Functions and Triggers (Properly Colocated by Table)
- **Item functions** (in item.sql):
  - `fn_item_add_desc()`: Helper - Add descendant with proper ascn_id
  - `fn_item_add_next()`: Helper - Add peer with same ascn_id
  - `fn_head_item_compose()`: Helper - Create flux by setting desc_id
  - `get_branch()`: Query - Get all descendants with flux detection
  - `item_in_flux()`: Query - Check if item is in flux condition
  - `fn_item_check_flux_constraint()`: Validation - Ensure flux items are heads
  - **Triggers**:
    - `trigger_item_delete_handle_deletion` (BEFORE DELETE)
    - `trigger_item_insert_update_check_ascn_cycle` (BEFORE INSERT/UPDATE)
    - `trigger_item_insert_update_check_flux_constraint` (AFTER INSERT/UPDATE)
- **Node triggers** (in node.sql):
  - `trigger_node_update_set_updated_at` (BEFORE UPDATE)
- **Data table functions** (each in their own migration):
  - `fn_data_text_update_node()` + `trigger_data_text_insert_update_update_node`
  - `fn_data_file_update_node()` + `trigger_data_file_insert_update_update_node`
  - `fn_data_user_create_head_item()` + `trigger_data_user_insert_create_head_item`
  - `fn_data_user_update_node()` + `trigger_data_user_update_update_node`
- **Access functions** (in access_control.sql):
  - `fn_node_check_access_flux()`: Flux-aware permission checking

### 7. Performance Optimizations
- Strategic indexes for common queries
- Composite indexes for flux detection
- Partial indexes for filtered queries
- ANALYZE commands for query optimization

## Implementation Status

### Completed
- ✅ Core infrastructure with proper types
- ✅ Node and core tables with indexes
- ✅ Item table with dual lineage support
- ✅ Access control tables and views
- ✅ Data tables (text, file, user) following template
- ✅ Helper functions for tree operations
- ✅ Deletion trigger handling all matrix cases
- ✅ Cycle detection for ascn_id chains
- ✅ FileType enum updated to match architecture (only 'png')
- ✅ All FK constraints have proper ON UPDATE CASCADE
- ✅ Function naming follows fn_<table>_<verb_object> pattern
- ✅ Comprehensive auth.md plan created

### Pending
- ⏳ RLS policies need review after auth plan
- ⏳ Testing framework (minimal due to invariant-based design)
- ⏳ Migration rollback scripts
- ⏳ Example usage documentation

### Architecture Compliance
- All invariants (I1-I8) are enforced through constraints
- All maxims (P1-P7) are implemented in triggers and functions
- Deletion matrix fully implemented
- Flux constraints enforced via triggers
- Permission model follows least-permissive principle

### Key Design Decisions Made
1. **Trigger vs Application Logic**: Critical constraints in triggers for invariance
2. **View-based Access Control**: node_permission view centralizes permission logic
3. **Automatic Workspace Creation**: Ensures every user has valid entry point
4. **Flux Validation**: Constraint trigger prevents invalid flux states
5. **Simple RLS Start**: Basic policies that can be enhanced based on usage