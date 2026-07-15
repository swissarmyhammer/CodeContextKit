---
assignees:
- claude-code
depends_on:
- 01KXK6VNT8YNZYEJB0KMM19ANQ
- 01KXK6W5F2XDBQ3SKG8FTZTRPW
- 01KXK6WVQ6584D77AK33NFTMJZ
position_column: todo
position_ordinal: '8780'
title: 'Document the two entry points: README section and plan.md design addendum'
---
## What
Document that the package now has two first-class ways in, and record the manager's design rationale where the codebase keeps its design record.

- `README.md`: add a "Two ways in" (or similarly named) section: standalone `CodeContext` for one repo (existing example stays) and `CodeContextManager` for multiple repos — a short manager usage snippet (discover → open → fan-out search with `Rooted` results) kept consistent with `Examples/ManagerExample/main.swift` so the shipped example is the compile-verified twin of the README snippet. Link both `Examples/` programs.
- `plan.md`: append a manager design section matching the style of the existing document, recording the agreed decisions the doc comments will reference: git repo = the project unit; three entry points over one open-or-get core; overlap rule (descendant → ancestor's context, ancestor of open roots → `overlappingRoot` error); keep-all-started lifecycle; fan-out + merge with partial failure; `ManagerState` aggregation with vacuous-ready semantics.

## Acceptance Criteria
- [ ] README shows both entry points with working snippets that match the example programs' code
- [ ] plan.md records the manager design decisions listed above
- [ ] No stale claims: README/plan.md statements match the shipped API names and behavior

## Tests
- [ ] `swift build` and `swift test` still pass (docs-only change; the example targets are what keep the snippets honest)

## Workflow
- Docs task: verify snippets against the built examples rather than TDD.