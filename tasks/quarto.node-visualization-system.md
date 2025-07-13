# Custom Node Visualization System for Quarto + mkultra Integration

**Status**: Planning  
**Priority**: High  
**Assignee**: Development Team  

## Overview

Create a Python-based node visualization system for Quarto documents that integrates with the mkultra utilities package, replacing the d2 dependency with a more flexible and controllable solution.

## Resources

- [Quarto Python Documentation](https://quarto.org/docs/computations/python.html)
- [Quarto Virtual Environments](https://quarto.org/docs/projects/virtual-environments.html)
- [IPython Display Documentation](https://ipython.readthedocs.io/en/stable/api/generated/IPython.display.html)
- [mkultra package repository](https://github.com/your-org/mkultra)

## Requirements

### Python Package Integration

- **Module Import**: Quarto executes Python code in Jupyter kernel environment
- **Package Access**: Can import any installed packages in active environment
- **Environment Management**: Use `quarto check jupyter` to verify setup
- **Development Flow**: Install mkultra package in development mode for live updates

### Core Functionality

1. **SVG Generation**: Create clean, customizable node diagrams
2. **Layout Algorithms**: Tree, hierarchy, and network layouts
3. **Interactive Features**: Expandable nodes, hover effects, click handlers
4. **Schema Integration**: Direct connection to database schema data
5. **Styling System**: Embedded CSS with theme support

### Integration Architecture

```python
# In mkultra package
from mkultra.apis.quarto import NodeDiagram, TreeLayout
from IPython.display import HTML

# Usage in Quarto docs
diagram = NodeDiagram(nodes, connections)
diagram.render()  # Returns HTML object
```

## Implementation Plan

### Phase 1: Core Infrastructure

1. **mkultra.quarto Module**: Create visualization module in mkultra package
2. **SVG Generator**: Basic shapes (rectangles, circles, lines, text)
3. **Layout Engine**: Simple tree and hierarchy algorithms
4. **CSS Integration**: Embedded styling system
5. **Quarto Testing**: Validate module imports and HTML output

### Phase 2: Schema-Specific Features

1. **Database Integration**: Connect to actual schema data
2. **Node Types**: Different visual styles for tables, views, functions
3. **Relationship Mapping**: Foreign keys, inheritance, dependencies
4. **Data Flow Visualization**: Show data movement and transformations

### Phase 3: Interactivity

1. **Expandable Trees**: Click to show/hide child nodes
2. **Hover Information**: Display detailed metadata
3. **Zoom/Pan Controls**: Navigate large diagrams
4. **Export Options**: Save as SVG, PNG, or HTML

## Technical Specifications

### Package Structure

```
mkultra/
├── apis/
│   └── quarto/
│       ├── __init__.py
│       ├── nodes.py          # Node diagram classes
│       ├── layouts.py        # Layout algorithms
│       ├── rendering.py      # SVG/HTML generation
│       └── styles.py         # CSS themes and styling
```

### Environment Setup

- Install mkultra in development mode: `pip install -e .`
- Verify Quarto can import: `quarto check jupyter`
- Test imports in Quarto: `from mkultra.apis.quarto import NodeDiagram`

### Development Workflow

1. **Local Development**: Edit mkultra package code
2. **Live Testing**: Changes reflected immediately in Quarto (dev install)
3. **Documentation**: Examples and usage in Quarto docs
4. **Global Availability**: Package available across all Quarto projects

## Advantages Over d2

- ✅ No external tool dependencies
- ✅ Full control over styling and behavior
- ✅ Direct database schema integration
- ✅ Python ecosystem compatibility
- ✅ Interactive capabilities
- ✅ Global availability via package install
- ✅ Much simpler syntax and maintenance

## Implementation Steps

### Step 1: Package Setup
- [ ] Create `mkultra/apis/quarto/` module structure
- [ ] Set up basic imports and exports
- [ ] Create development environment setup script

### Step 2: Basic SVG Generation
- [ ] Implement `NodeDiagram` class
- [ ] Create SVG primitives (rectangle, circle, line, text)
- [ ] Build coordinate system and viewport management
- [ ] Add basic styling support

### Step 3: Layout Algorithms
- [ ] Implement `TreeLayout` for hierarchical structures
- [ ] Create `NetworkLayout` for graph relationships
- [ ] Add automatic spacing and positioning
- [ ] Handle edge routing and collision detection

### Step 4: Quarto Integration
- [ ] Test module imports in Quarto environment
- [ ] Validate HTML output rendering
- [ ] Create example documentation
- [ ] Set up CSS theming system

### Step 5: Schema Integration
- [ ] Connect to database metadata
- [ ] Map table relationships to visual connections
- [ ] Implement node types for different schema objects
- [ ] Add data flow visualization

### Step 6: Interactivity
- [ ] Implement JavaScript for node expansion
- [ ] Add hover effects and tooltips
- [ ] Create zoom/pan controls
- [ ] Build export functionality

## Acceptance Criteria

1. **Basic Functionality**: Can create simple node diagrams with connections
2. **Quarto Integration**: Imports work seamlessly in Quarto documents
3. **Schema Visualization**: Displays database schema relationships accurately
4. **Performance**: Renders large diagrams (100+ nodes) efficiently
5. **Customization**: Supports custom styling and themes
6. **Documentation**: Complete usage examples and API documentation

## Success Metrics

- Replacement of all d2 diagrams in existing documentation
- Improved diagram load times and responsiveness
- Ability to generate interactive schema documentation
- Simplified syntax compared to d2 markup

## Discussion

This approach provides a robust, maintainable solution that leverages Python's strengths while giving us complete control over the visualization system. The integration with mkultra ensures the functionality is available across all projects and can evolve with our needs.

## Exclusions

- **3D Visualizations**: Focus on 2D diagrams only
- **Real-time Data**: Static diagrams, not live data feeds
- **Complex Animations**: Simple transitions only
- **Mobile Optimization**: Desktop-first approach initially