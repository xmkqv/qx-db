# Authentication and Authorization Plan

This document defines the comprehensive authentication and authorization strategy for the Dual Lineage Tree Architecture.

## Core Principles

### From Architecture Invariants

- **I7: Permission Authority**: Nodes are the authoritative source for all access control
- **P7: Flux-Aware Permissions**: 
  - Native descendants inherit stem permissions naturally
  - Flux descendants require checks on both lineages
  - Least permissive wins at flux boundaries
  - Security preserved across tree composition

## Authentication Model

### External Auth Provider
- Using auth.users(id) references implies external authentication provider
- Assumed: Supabase Auth or similar PostgreSQL-compatible auth schema
- User IDs are UUIDs that can change (ON UPDATE CASCADE required)

### User Identity
- Each user has a UUID from the auth system
- Users are represented as nodes with type 'user' in our system
- data_user table links auth UUID to our node system

## Authorization Model

### Permission Types
```sql
PermissionType: ENUM('view', 'edit', 'admin')
```

### Permission Hierarchy
- **view**: Read-only access to node and its data
- **edit**: Can modify node data and create relationships
- **admin**: Full control including granting permissions and deletion

### Access Sources

1. **Creator Access**
   - Node creators automatically have 'admin' permission
   - Tracked via node.creator_id
   - Survives even if creator is deleted (ON DELETE SET NULL)

2. **Explicit Grants**
   - Stored in node_access table
   - One permission per node-user pair
   - Most permissive wins if multiple paths exist

3. **Link Access**
   - Separate permissions for link entities
   - Independent from node permissions
   - Required for link visibility and manipulation

## Dual Lineage Permission Model

### Native Descendants
- Items where `item.ascn_id = stem.id`
- Inherit permissions from their stem naturally
- No special handling required

### Flux Descendants
- Items where `item.ascn_id ≠ stem.id` (composed from another tree)
- Require permission checks on BOTH lineages:
  1. Ascendant lineage (where item came from)
  2. Stem lineage (where item is composed into)
- **Least permissive wins**: Must have required permission via BOTH paths

### Permission Check Algorithm
```
CHECK_ACCESS(node_id, user_id, required_permission):
  1. Check direct node access (creator or explicit grant)
  2. If node is part of item, check if flux condition exists
  3. If flux:
     a. Check permission via stem lineage
     b. Check permission via ascendant lineage
     c. Return TRUE only if BOTH grant required permission
  4. Return direct access result
```

## Implementation Strategy

### Access Control Tables
1. **node_access**: Node-level permissions
2. **link_access**: Link-level permissions
3. **accessible_nodes view**: Consolidated view of all accessible nodes

### Row Level Security (RLS)

#### Design Principles
- All tables MUST have RLS enabled
- Data tables delegate to node permissions
- Policies should be simple and performant
- Flux-aware policies only where necessary

#### Policy Patterns

1. **Node Table Policies**
   ```sql
   -- SELECT: Users see nodes they have any permission on
   -- INSERT: Users can create nodes (become creator)
   -- UPDATE: Users need edit or admin permission
   -- DELETE: Users need admin permission
   ```

2. **Data Table Policies**
   ```sql
   -- All operations delegate to node permissions
   -- Single policy: "Data follows node access"
   ```

3. **Item Table Policies**
   ```sql
   -- Must consider flux conditions
   -- Check both lineages for flux items
   ```

4. **Link Table Policies**
   ```sql
   -- Separate from node permissions
   -- Both src and dst must be accessible
   ```

### User Workspace Security

1. **Workspace Creation**
   - Each user gets automatic root item on creation
   - User has admin access to their workspace root
   - Workspace is private by default

2. **Workspace Sharing**
   - Users can grant permissions on their nodes
   - Shared subtrees maintain original permissions
   - Composed trees respect both lineages

## Security Boundaries

### Flux Points
- Composition creates security boundaries
- Original tree permissions preserved
- Cannot bypass permissions via composition
- Deletion blocked for flux items (per P3)

### Permission Propagation
- Permissions do NOT automatically propagate to descendants
- Each node has independent access control
- Composition does not grant implicit access

### Audit Considerations
- node_access tracks explicit grants only
- Creator access implicit via node.creator_id
- No audit trail for permission changes (out of scope)

## Implementation Notes

### Performance Optimization
- accessible_nodes view pre-computes access
- Indexed on (node_id, user_id) for fast lookups
- Flux checks only when necessary

### Future Considerations
- Group-based permissions (not in current scope)
- Time-based access (not in current scope)
- Permission delegation chains (not in current scope)

## Invariant Preservation

### How This Design Maintains Invariants

1. **I7 (Permission Authority)**: 
   - All access control centers on nodes
   - No bypass mechanisms exist
   - Clear permission model

2. **P7 (Flux-Aware Permissions)**:
   - Explicit handling of flux conditions
   - Least permissive model prevents security holes
   - Both lineages must grant access

3. **Security by Design**:
   - RLS enforces permissions at database level
   - No application-level bypass possible
   - Consistent permission model throughout