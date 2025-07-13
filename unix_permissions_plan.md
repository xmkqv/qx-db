# Unix Permission System for qx-db: Phased Implementation

## Overview

This plan implements Unix-style permissions in phases, starting with the absolute minimum and building only as needed. Each phase is backward compatible and can be deployed independently.

## Phase 1: Basic 9-Bit System (Minimal Change)

### What Changes
- Expand permission_bits from 3 to 9 bits
- Keep existing permission logic, just shifted
- No new tables, no complex logic

### Bit Layout
```
Bits: 8 7 6 | 5 4 3 | 2 1 0
      U U U | G G G | O O O
      r w x | r w x | r w x

User (6-8):  What the specific user can do
Group (3-5): What group members can do (unused initially)
Other (0-2): What everyone else can do (unused initially)
```

### Implementation

#### 1.1 Schema Migration
```sql
-- Expand constraint to 9 bits
ALTER TABLE node_access 
  DROP CONSTRAINT node_access_permission_bits_check;
ALTER TABLE node_access 
  ADD CONSTRAINT node_access_permission_bits_check 
  CHECK (permission_bits >= 0 AND permission_bits <= 511);

-- Migrate existing permissions to user bits
-- Current: bit 0=admin(1), bit 1=edit(2), bit 2=view(4)  
-- New: these become bits 6=admin(1), 7=edit(2), 8=view(4)
UPDATE node_access 
SET permission_bits = permission_bits << 6;
```

#### 1.2 Update Trigger for New Nodes
```sql
-- Update the auto-grant trigger to use new bit positions
CREATE OR REPLACE FUNCTION fn_node_grant_creator_admin()
RETURNS TRIGGER AS $$
BEGIN
  -- Grant full user permissions (7 << 6 = 448 = 0700 octal)
  INSERT INTO node_access (node_id, user_id, permission_bits)
  VALUES (NEW.id, auth.uid(), 448);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 1.3 Simple Permission Check
```sql
-- Basic check - only looks at user bits
CREATE OR REPLACE FUNCTION user_has_node_access(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY INVOKER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM node_access
    WHERE node_id = p_node_id 
    AND user_id = auth.uid()
    AND ((permission_bits >> 6) & p_required_bits) = p_required_bits
  );
$$;
```

#### 1.4 Update RLS Policies
```sql
-- Just update bit positions in existing policies
-- No logic changes, just bit math
CREATE POLICY "Users can view nodes they have access to" ON node
  FOR SELECT
  USING (user_has_node_access(id, 4));  -- View = bit 2 = 4

CREATE POLICY "Users can update nodes they have edit access to" ON node
  FOR UPDATE
  USING (user_has_node_access(id, 2))   -- Edit = bit 1 = 2
  WITH CHECK (user_has_node_access(id, 2));

CREATE POLICY "Users can delete nodes they have admin access to" ON node
  FOR DELETE
  USING (user_has_node_access(id, 1));  -- Admin = bit 0 = 1
```

### What This Gives You
- ✅ Existing system keeps working
- ✅ Room to grow (group and other bits available)
- ✅ Standard Unix bit positions
- ✅ Minimal migration risk

## Phase 2: Add Public Access (When Needed)

### When to Implement
- When you need nodes that anyone can read
- When you want default permissions for non-specified users

### Implementation

#### 2.1 Enhanced Permission Check
```sql
CREATE OR REPLACE FUNCTION user_has_node_access_v2(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY INVOKER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM node_access
    WHERE node_id = p_node_id 
    AND (
      -- Check user bits if this is the user's entry
      (user_id = auth.uid() AND ((permission_bits >> 6) & p_required_bits) = p_required_bits)
      OR
      -- Check other bits from any entry (public access)
      ((permission_bits & p_required_bits) = p_required_bits)
    )
  );
$$;
```

#### 2.2 Public Node Example
```sql
-- Make a node publicly readable
INSERT INTO node_access (node_id, user_id, permission_bits)
VALUES (
  123,                    -- node_id
  auth.uid(),            -- creator gets full access
  448 + 4                -- 0704 octal (user=rwx, other=r)
);
```

## Phase 3: Add Group Support (When Needed)

### When to Implement
- When you need shared workspaces
- When you want role-based permissions
- When managing individual permissions becomes unwieldy

### How Groups Work
- Groups are just nodes (everything is a node)
- Group membership = user's node is in group's item tree
- No new tables needed

### Implementation

#### 3.1 Group-Aware Permission Check
```sql
CREATE OR REPLACE FUNCTION user_has_node_access_v3(
  p_node_id INTEGER,
  p_required_bits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_user_node_id INTEGER;
  v_has_permission BOOLEAN := FALSE;
BEGIN
  -- Get user's node_id
  SELECT node_id INTO v_user_node_id 
  FROM data_user WHERE user_id = auth.uid();

  -- Check direct user permissions and other permissions
  SELECT EXISTS (
    SELECT 1 FROM node_access
    WHERE node_id = p_node_id 
    AND (
      -- User bits
      (user_id = auth.uid() AND ((permission_bits >> 6) & p_required_bits) = p_required_bits)
      OR
      -- Other bits
      ((permission_bits & p_required_bits) = p_required_bits)
    )
  ) INTO v_has_permission;

  IF v_has_permission THEN
    RETURN TRUE;
  END IF;

  -- Check group permissions
  -- User is in group if their node is in group's item tree
  RETURN EXISTS (
    WITH user_groups AS (
      SELECT ancestor_item.node_id AS group_node_id
      FROM item user_item
      JOIN item ancestor_item ON user_item.ascn_id = ancestor_item.id
      WHERE user_item.node_id = v_user_node_id
    )
    SELECT 1 
    FROM user_groups ug
    JOIN data_user du ON du.node_id = ug.group_node_id
    JOIN node_access na ON na.user_id = du.user_id
    WHERE na.node_id = p_node_id
      AND ((na.permission_bits >> 3) & p_required_bits) = p_required_bits
  );
END;
$$;
```

## Phase 4: Prevent Orphaned Nodes (When Needed)

### When to Implement
- When you have shared resources
- When users can be deleted
- When you need ownership succession

### Implementation

#### 4.1 Simple Orphan Prevention
```sql
CREATE OR REPLACE FUNCTION fn_prevent_last_admin_removal()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_count INTEGER;
BEGIN
  -- Only care about removing admin permission
  IF OLD.user_id = NEW.user_id AND 
     ((OLD.permission_bits >> 6) & 1) = 1 AND 
     ((NEW.permission_bits >> 6) & 1) = 0 THEN
    
    -- Count other admins
    SELECT COUNT(*) INTO v_admin_count
    FROM node_access
    WHERE node_id = OLD.node_id
      AND user_id != OLD.user_id
      AND ((permission_bits >> 6) & 1) = 1;
    
    IF v_admin_count = 0 THEN
      RAISE EXCEPTION 'Cannot remove last admin from node %', OLD.node_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_orphaned_nodes
  BEFORE UPDATE ON node_access
  FOR EACH ROW
  EXECUTE FUNCTION fn_prevent_last_admin_removal();
```

## Phase 5: Special Bits (When Needed)

### When to Implement
- Sticky bit: When you need protected shared spaces
- Setgid bit: When you want permission inheritance
- Setuid bit: When you need succession planning

### Upgrade to 12 Bits
```sql
-- Extend to 12 bits
ALTER TABLE node_access 
  DROP CONSTRAINT node_access_permission_bits_check;
ALTER TABLE node_access 
  ADD CONSTRAINT node_access_permission_bits_check 
  CHECK (permission_bits >= 0 AND permission_bits <= 4095);
```

### Special Bit Meanings
- **Bit 9 (Sticky)**: Only admins can delete
- **Bit 10 (Setgid)**: Children inherit group permissions  
- **Bit 11 (Setuid)**: User marked as successor

## Migration Path

### Current State → Phase 1
```sql
-- Single UPDATE to shift bits
UPDATE node_access SET permission_bits = permission_bits << 6;
```

### Phase 1 → Phase 2
- Just deploy new function
- Update RLS policies to use v2 function
- No data migration needed

### Phase 2 → Phase 3
- Deploy v3 function
- Update RLS policies
- Create groups by making nodes

### Phase 3 → Phase 4
- Add trigger
- No data changes needed

### Phase 4 → Phase 5
- Extend constraint to 12 bits
- Add special bit logic as needed

## Common Permission Patterns

### Phase 1 Patterns (User only)
- `448` (0700): Private node - user full access
- `384` (0600): User read/write, no admin
- `256` (0400): User read-only

### Phase 2 Patterns (User + Other)
- `452` (0704): User full, public read
- `436` (0664): User rw, public read
- `292` (0444): Everyone read-only

### Phase 3 Patterns (User + Group + Other)
- `488` (0750): User full, group read/exec
- `508` (0774): User full, group full, other read
- `432` (0660): User and group read/write

### Phase 5 Patterns (With special bits)
- `1980` (3774): Sticky + setgid, group collaborative
- `2492` (4754): Setuid succession, controlled access
- `1023` (1777): Full public with sticky (like /tmp)

## Benefits of Phased Approach

1. **Low Risk**: Each phase is small and tested
2. **Backward Compatible**: Never breaks existing code
3. **Pay As You Go**: Only implement what you need
4. **Easy to Understand**: Start simple, add complexity gradually
5. **Quick Wins**: Phase 1 can deploy immediately

## Current Recommendation

1. **Implement Phase 1 now** - It's just a bit shift
2. **Add Phase 4** - Prevent orphaned nodes (critical)
3. **Implement other phases as needed**

This gives you a solid foundation with room to grow.