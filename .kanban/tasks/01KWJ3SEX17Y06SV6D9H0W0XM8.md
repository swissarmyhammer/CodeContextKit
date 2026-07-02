---
depends_on:
- 01KWJ3PSVZTXYZDX1ASZ3GN09M
- 01KWJ3QTH53M16194BCTX6MKVP
position_column: todo
position_ordinal: 8b80
title: 'queryAST op: runtime S-expression queries'
---
## What
Create `Sources/CodeContextKit/Ops/QueryAST.swift` — port of `crates/swissarmyhammer-code-context/src/ops/query_ast.rs`. Compile a user-supplied tree-sitter S-expression query at runtime for a named language (via `Languages.all`), run it against files on disk under the root — **enumerated via the shared `Walker` (gitignore-aware), filtered to that language's extensions; do not re-implement gitignore semantics** — and return `QueryASTResult { matches: [ASTMatch(file, captures)], filesScanned }` with a max-results cap. Invalid query text → thrown typed error with the tree-sitter message, not a crash.

## Acceptance Criteria
- [ ] A `(function_item name: (identifier) @name)` query over a rust fixture returns the expected capture names and ranges
- [ ] Malformed query throws a descriptive error; unknown language throws
- [ ] `maxResults` truncates and reports `filesScanned` accurately; gitignored files are never scanned

## Tests
- [ ] `Tests/CodeContextKitTests/QueryASTTests.swift`: capture correctness on fixtures, error paths, cap behavior, gitignore exclusion
- [ ] Run `swift test --filter QueryASTTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.