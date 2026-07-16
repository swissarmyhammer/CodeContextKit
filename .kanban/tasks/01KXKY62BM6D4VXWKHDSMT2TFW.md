---
assignees:
- claude-code
depends_on:
- 01KXKY5MDHKKE49ZX9BA2H6BDJ
position_column: todo
position_ordinal: '8480'
title: 'Document LSP auto-install: README, plan.md, and example opt-out'
---
## What
Record the auto-install behavior where users and future maintainers will look:

- `README.md`: a short "Language servers" section — servers auto-install by default when a project is detected and the binary is missing (native global installers: rustup/npm/go/pipx/brew, each gated on the installer tool being present); the per-server table (server → install command → hint-only ones: sourcekit-lsp, clangd); how to opt out (`LspAutoInstall(isEnabled: false)` on `CodeContext`/`CodeContextManager` init) and adjust the timeout.
- `plan.md`: append the design record matching the existing document's style: `InstallSpec` on `ServerSpec` (nil = hint-only), `ServerInstaller` with the `InstallRunner` seam and at-most-once guarantee, the `.notFound → .installing → forceRestart → .running/.notFound` supervisor flow running as owned non-blocking tasks, `extraSearchDirectories` rationale (`~/go/bin`, `~/.cargo/bin` not on `$PATH`), on-by-default opt-out policy decision.
- `Examples/`: mention the `autoInstall:` parameter in whichever example's header comment fits (one line — the defaults mean no code change is required for the examples to benefit).

## Acceptance Criteria
- [ ] README documents default-on behavior, the per-server install table, and the opt-out — all names matching the shipped API
- [ ] plan.md records the design decisions above
- [ ] No stale claims versus the implemented behavior

## Tests
- [ ] `swift build` and `swift test` still pass (docs-only change)

## Workflow
- Docs task: verify statements against the shipped code rather than TDD.