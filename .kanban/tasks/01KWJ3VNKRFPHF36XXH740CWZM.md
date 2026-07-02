---
depends_on:
- 01KWJ3SX2N6BCJ6APE16W6TVAR
- 01KWJ3TB95F2J0CZYW17DCP9H8
position_column: todo
position_ordinal: '9280'
title: 'callGraph and blastRadius ops: BFS over call edges'
---
## What
Create `Sources/CodeContextKit/Ops/CallGraph.swift` + `BlastRadius.swift` — ports of `ops/get_callgraph.rs` and `ops/get_blastradius.rs`. `callGraph(of:direction:maxDepth:)`: resolve start symbol (name via getSymbol tiers, or file:line:char), BFS over `lsp_call_edges` (both 'lsp' and 'treesitter' sources), direction inbound/outbound/both, depth clamped 1…5; returns `CallGraph { root, nodes, edges(depth, source) }`. `blastRadius(file:symbol:maxHops:)`: root symbols in a file (optionally name-filtered), inbound BFS clamped 1…10, per-hop aggregation → `BlastRadius { roots, hops: [HopLevel(symbols, affectedFiles)], totals }`. Whole-file with no symbols → empty result; named symbol missing → notFound error.

## Acceptance Criteria
- [ ] On a fixture graph A→B→C→A (cycle), BFS terminates and each node appears once per traversal
- [ ] maxDepth/maxHops clamping enforced; direction filters honored
- [ ] blastRadius hop levels aggregate affected files without duplicates across hops

## Tests
- [ ] `Tests/CodeContextKitTests/CallGraphTests.swift`: seeded edge fixtures — cycle termination, depth clamps, direction, hop aggregation goldens, notFound path
- [ ] Run `swift test --filter CallGraphTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.