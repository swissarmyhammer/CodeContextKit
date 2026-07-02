---
depends_on:
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: todo
position_ordinal: 8c80
title: Tree-sitter call-edge heuristic
---
## What
Create `Sources/CodeContextKit/TreeSitter/TSCallGraph.swift` — port of `crates/swissarmyhammer-code-context/src/ts_callgraph.rs`. Walk parsed ASTs for call-expression node kinds (`call_expression`, `method_call_expression`, `call`, …), extract callee names via function/method field lookup (after-last-dot for member access), resolve against `ts_chunks.symbol_path` suffix matching, write `lsp_call_edges` rows with `source = 'treesitter'`. Wire into the tree-sitter worker so edges are produced in the same drain pass as chunks.

## Acceptance Criteria
- [ ] A swift fixture where `caller()` invokes `Helper.doWork()` yields an edge caller→Helper.doWork with source 'treesitter'
- [ ] Unresolvable callees (no matching symbol_path) produce no edge and no error
- [ ] Edges are replaced, not duplicated, when a file is re-indexed

## Tests
- [ ] `Tests/CodeContextKitTests/TSCallGraphTests.swift`: edge extraction goldens for swift + rust fixtures; re-index idempotency; unresolved-callee case
- [ ] Run `swift test --filter TSCallGraphTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.