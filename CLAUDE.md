# Guide

**Perfect design is irreducible**

## Roles

- **Designer**: Creates the initial design, structure, and vision for a project
- **Agent**: The autonomous intelligence addressed by this document—a capable system with extensive skills beyond self-awareness.

## Collaboration

- **Dialogue**:
  - Honest, insightful, and curious
- **Avoid**
  - Sycophantic responses or unwarranted positivity
  - Superficial agreement or disagreement
  - Flattery that doesn't serve the discussion
  - Generic usage of emojis; use them intentionally when they add strong emphasis
- **[read-only]CLAUDE.md**: Contains features, guidance, and documentation for the Collaborators
  - **Features**: The complete set of features: No more, no less.
    - When complete, each Feature must be documented in the README.md.
    - If **no** features are defined yet **and** the project already has functionality: the Agent MUST OFFER to document existing functionality - if allowed, this is the only case the Agent should modify the CLAUDE.md.
- **README.md**: Collaborative planning space
- **Actions**: `@` prefixed comments intended to communicate with the Agent, such as `@agent: Please review this section`. Should be removed after the Agent has addressed them. Exclusion: `@lock` - action analogue to `[read-only]` for lines & sections that should not be modified.

**If it is not defined in the CLAUDE.md: IT IS NOT A FEATURE AND SHOULD NOT BE IMPLEMENTED.**

- The only exceptions are utilities and tools extracted from features to deduplicate code and improve maintainability.

## Conventions

- `qx`: always lowercase
- `...`: Placeholder value
- `[read-only]`: Section locked from Agent modification
- `*`: Wildcard, eg `hello_world.*` means all methods in the `hello_world` module
- Common Accepted Shorthands:
  - `gen`: Generate, eg command `gen hello_world` | generated code directory `gen/hello_world`
  - `prod`: Production, eg `test prod`
  - `dev`: Development, eg `test dev`

## Interfaces

- **Types**: For universality, use semantic names `string|float|integer|boolean|...` OR the language-specific types in interface definitions

### project

- **Syntax**: `./.../...`: description/further nesting
- **Naming**: Unless specified, paths are relative to the project workspace directory

### cli

- **Syntax**: `command --<key> <string> ...`: description
- **Example**: `app hello-world post --text <string>`: Publish hello world with custom text

### module

- **Syntax**: `module.verb_object(...arguments) -> return_type`: description
- **Naming**: Snake case for methods following `verb_object` or `an_expressive_name` patterns
- **Example**: `hello_world.create_file(path: string) -> boolean`: Create hello world document

### api

- **Syntax**: `<METHOD> /.../...: description (...arguments) -> return_type`
- **Example**: `POST /api/messages: Send message (body: Message) -> MessageResponse`

### db

- **Syntax**: `TableName.operation`: description
- **Naming**: PascalCase for tables, optional CRUD operation suffix
- **Example**: `UserAccount.find(...params)`: Retrieve user by parameters
- **CRUD methods pattern**
  - Class methods:
    - `get(id)`: retrieve by ID, error if not found. Wraps `find(id)`
    - `find(...params)`: retrieve by params, return null if not found. Wraps `findn(1, ...params)`
    - `findn(limit: integer, ...params)`: retrieve by params, return list if not found
    - `add(...params)`: add a new object, error if ID already exists
    - `del(id)`: delete by ID, error if not found
  - Instance methods:
    - `set_()`: set the object, replacing existing data
    - `add_()`: add the object, error if ID already exists
    - `del_()`: delete the object, error if not found
  - **Syntax**: `TableName.operation(...params)`

### function

- **Syntax**: `function_name(...arguments) -> return_type` | `functionName(...arguments) -> returnType`: description
- **Naming**: language dependent casing, following `verb_object` or `an_expressive_name` patterns
- **Example**: `hello_world.validate_input(text: string) -> boolean`: Validate hello world input text
- **Testing**: Inline or infile unit tests

### flow

- **Syntax**: `flow_name(...) -> outcome`: description
- **Naming**: Same as functions but less strict, if composed of other functions/flows state the sequence
- **Example**: `hello_world.gen_article(text: string, output: string) -> PublishResponse`: Generate and publish hello world article
  - `hello_world.gen_article('Hello, World!', 'api') -> article`
  - `hello_world.publish_article(article, URL)`

# [read-only]Features

## Phase 1: Foundation

Core database schema providing a universal data layer with polymorphic node system.

### db

- `node`: Universal entity table for all data types (id, type, created_at, updated_at)
- `root`: Authentication linkage between auth.users and nodes
- `link`: Semantic relationships between nodes (src_id, dst_id)
- `item`: Hierarchical relationships (node_id, desc_id, next_id, tile_id)
- `text`: Text content storage (node_id, content)
- `file`: File metadata storage (node_id, type, bytes, uri)
- `tile`: Visual rendering configuration (x, y, w, h, viewbox, layout, visual, anchor)
- `data_user`: User profile data (node_id, username, display_name, bio, avatar_url, preferences)

### function

- `trigger_set_updated_at() -> trigger`: Automatic timestamp updates
- `get_dsts(src_id: integer) -> node[]`: Get destination nodes from links
- `get_srcs(dst_id: integer) -> node[]`: Get source nodes from links
- `get_items(item_id: integer, variants?: jsonb) -> item[]`: Get items by ID
- `trigger_data_insert() -> trigger`: Auto-create nodes when data inserted
- `check_node_has_data() -> trigger`: Constraint ensuring nodes have data
- `get_nbrs(node_id: integer) -> table(neighbor_id: integer, relationship_type: text)`: Get all neighbors

### flow

```mermaid
%%{init: {'theme': 'dark'}}%%
graph TD
  %% Data insertion flow
  ([data])
  [(node)]
  [(data_*)]
  
  %% Triggers
  [trigger_data_insert]
  [trigger_set_updated_at]
  [check_node_has_data]
  
  %% Flow
  ([data]) --> [trigger_data_insert]
  [trigger_data_insert] --> [(node)]
  [trigger_data_insert] --> [(data_*)]
  [(data_*)] --> [trigger_set_updated_at]
  [trigger_set_updated_at] --> [(data_*)]
  [(node)] -.-> [check_node_has_data]
  [check_node_has_data] -.-> [(data_*)]
```

## Phase 2: Data Types (Not Started)

Extensible polymorphic data system with automatic schema generation.

### cli

- `qx add-data-type --name <string> --fields <json>`: Add new data types with automatic schema generation

### api

- `POST /api/nodes`: Create nodes of any type `(type: string, data: object) -> {id: string, node: Node}`
- `GET /api/nodes/:id`: Retrieve any node with its data `(node_id: string) -> Node & Data`
- `POST /api/links`: Create semantic relationships `(src_id: string, dst_id: string, predicate?: string) -> Link`

### cli

- `qx generate-types`: Auto-generate TypeScript types from schema

### flow

```mermaid
%%{init: {'theme': 'dark'}}%%
graph TB
  %% CLI command
  [qx add-data-type --name example --fields '{...}']
  
  %% Processing
  [parse_fields]
  [validate_schema]
  [generate_migration]
  
  %% Database operations
  [ALTER TYPE NODETYPE]
  [(data_example)]
  [add_triggers]
  [update check_node_has_data]
  
  %% Results
  ([migration.sql])
  ([types.ts])
  
  %% Flow
  [qx add-data-type --name example --fields '{...}'] --> [parse_fields]
  [parse_fields] --> [validate_schema]
  [validate_schema] --> [generate_migration]
  [generate_migration] --> [ALTER TYPE NODETYPE]
  [ALTER TYPE NODETYPE] --> [(data_example)]
  [(data_example)] --> [add_triggers]
  [add_triggers] --> [update check_node_has_data]
  [update check_node_has_data] --> ([migration.sql])
  ([migration.sql]) --> ([types.ts])
```

## Phase 3: Graph Operations (Not Started)

Efficient relationship traversal and real-time capabilities.

### module

- `graph.traverse(start_node: integer, depth: integer, filters?: Filter[]) -> Graph`: Navigate relationships efficiently

### api

- `POST /api/subscribe`: Real-time updates via Supabase `(filters: Filter[]) -> Subscription`
- `POST /api/batch`: Efficient bulk operations `(operations: Operation[]) -> Result[]`

### module

- `search.vector(embedding: float[], threshold: float) -> node[]`: Vector search capabilities
- `query.time_travel(timestamp: string) -> Snapshot`: Historical data viewing

# Style

## Diagrams

- **Mermaid**: Use Mermaid syntax for diagrams
- **Theme**: `%%{init: {'theme': 'dark'}}%%`
- **Object**: `([name])` — eg variables, arguments, returns, config, user input, responses, files
- **Function**: `[name]` — eg processing steps, methods, operations, actions
- **Switch**: `{{name}}` — eg decision points, conditionals, flow splitters
- **Database**: `[(name)]` — eg stores, storage operations, data persistence layer
- **Service**: `((name))` — eg external services, APIs, third-party integrations, apps, systems, or services
- **Relationships**: `-->` solid line, `-.->` dotted line for conditional alternatives or data

## Code

**Pretty code is good code**

- Simple
- Readable
- Assert/Return/Raise early
  - eg:
    - Given a path variable. This path is used in many places. Assert the path exists at point of origin. Not at every usage.
- Uses modern idioms, conventions, and patterns

### Python

- **Stack**:
  - 3.13+
  - Package manager: `uv`
  - Testing: `pytest` + `doctest`, infile tests, config & special cases in `./tests`
  - Linter: `ruff`
  - Formatter: `ruff`
- **Imports**: Full path imports of namespaces, eg `from qx_ai.lib import hello_world`
- **Nits**:
  - `from typing import List, Dict` < `list` & `dict`
  - `os.getenv(...)` < `os.environ[...]`
  - `Optional[Example]` < `Example | None`

### Typescript

- **Stack**:
  - Package manager: `pnpm`
  - Testing: `vitest`
  - Linter: `eslint`
  - Formatter: `prettier`
  - Dev: `vite`
  - Framework: `solid-js`
- **Nits**:
  - `function fn(...) ...` < `const fn = (...) => ...`
  - `nodeStore` < `nodes`

## Writing

**Good writing has rhythm. Great writing has tides.**

### Core Principles

#### 1. Give Numbers Context

Data without story is noise. Data with meaning creates understanding.

- **Surface**: "The error rate is 50-80%"
- **Depth**: "Predictions fail more often than they succeed"
- **Current**: "In an industry that measures fuel by the gram, we navigate by approximation"
- **Professional**: "Current models achieve 20-50% accuracy—insufficient for operational requirements"

#### 2. Compress for Clarity

Precision creates power. Every word should earn its place.

- **Verbose**: "The company has developed innovative solutions leveraging cutting-edge technology"
- **Clear**: "We solved persistent industry challenges"
- **Precise**: "We transformed uncertainty into actionable intelligence"

#### 3. Bridge Technical Divides

Make complexity accessible without sacrificing accuracy.

- **Opaque**: "Atmospheric ice-supersaturation enables contrail persistence"
- **Clearer**: "Specific humidity conditions allow contrails to linger"
- **Bridged**: "When conditions align, temporary trails become lasting climate impacts"

#### 4. Select Verbs Deliberately

Verbs reveal. Choose ones that illuminate rather than overwhelm.

- **Passive**: "Data is processed by the system"
- **Active**: "The system processes data"
- **Revealing**: "The system translates atmospheric signals into operational intelligence"

#### 5. Create Subtle Echoes

Introduce themes early. Let them resurface naturally.

- Opening metaphor: ocean/navigation
- Middle development: currents/depths
- Resolution: charting new waters

#### 6. Scale Thoughtfully

Connect vast concepts to tangible impacts.

- **Abstract**: "Significant environmental impact"
- **Scaled**: "$87 million daily climate cost"
- **Contextualized**: "Each flight's hidden climate invoice"

### Advanced Techniques

#### The Professional Paradox

Maintain expertise while remaining approachable. Authority need not intimidate.

- "The model's limitations became apparent under stress"
- "Unexpected patterns emerged from the data"
- "Traditional approaches met modern challenges"

#### The Conceptual Bridge

Connect familiar to novel without condescension.

- "Like reading tomorrow's weather in today's patterns"
- "Transforming atmospheric whispers into operational wisdom"
- "Where precision meets prediction"

#### The Technical Translation

Balance accuracy with accessibility.

- "Schmidt-Appleman criterion—the physics governing contrail formation"
- "62.1 mW/m² warming impact—significant despite its modest appearance"
- "Ice-supersaturation—when humidity exceeds natural thresholds"

#### Temporal Compression

Reveal patterns through time perspective.

- "A century from first flight to climate accountability"
- "Innovation outpacing comprehension"
- "Yesterday's breakthrough, today's challenge"

### Rhythm and Structure

Vary sentence length naturally:

- Short sentences anchor ideas.
- Medium length constructs develop concepts and meaning.
- Longer sentences allow for nuance and complexity while maintaining clarity through careful structure.
- Return to brevity.
- Build again.

### The Reader's Journey

Every piece should:

1. Respect the reader's intelligence
2. Reward their attention
3. Advance their understanding
4. Leave them curious, not confused

### Quality Markers

Ask yourself:

- Would an expert respect this?
- Would a newcomer understand it?
- Does it add value to the conversation?
- Is the creativity serving clarity?

### The Subtle Spark

Let brilliance emerge through:

- Unexpected connections (sparingly)
- Elegant compression
- Perfect verb choice
- Structural surprise
- Conceptual clarity

Remember: The goal is not to impress with cleverness but to illuminate with insight. Like the ocean, maintain a professional surface while allowing glimpses of the depths beneath.

# Predefined Flows

## Gist Preview

- `gh gist create [file] --public --desc "[description]"`: Create Github gist
- print `https://gist.githack.com/[user]/[id]/raw/[file]`
  - Renders HTML with proper MIME types
  - No GitHub interface framing
  - Fast and reliable preview links

# End of Guide

**Perfect design is irreducible**