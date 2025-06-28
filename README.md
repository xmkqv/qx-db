## Supabase Auth Schema

- auth
  - .users: User accounts @refine
  - .identities: OAuth identities @refine
  - .sessions: Active sessions @refine
  - .refresh_tokens: Refresh tokens @refine

# I: Schema

- public
  - [ ] .data\_<type>: various data tables
  - [ ] .node: Data index and proxy
  - [ ] .link: Semantic relationships
  - [ ] .item: Structure
    - [ ] `get_roots(auth.id)`: Get root items for a user
  - [ ] .tile: Render
