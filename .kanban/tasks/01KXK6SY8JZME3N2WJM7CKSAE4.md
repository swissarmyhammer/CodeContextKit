---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'Add RootDiscovery: find git-repo roots under a parent and resolve the repo root containing a path'
---
## What
Create `Sources/FoundationModelsCodeContext/Projects/RootDiscovery.swift` with a `public enum RootDiscovery` (stateless namespace, mirroring `ProjectDetection`):

- `public static func discoverRoots(under parent: URL) throws -> [URL]` — its own FileManager traversal (deliberately NOT `Walker.walkEntries`: Walker skips hidden entries so it can never see `.git`). Rules:
  - A directory containing a `.git` entry is a repo root. `.git` may be a **directory** (normal repo) or a **file** (worktree/submodule) — both count.
  - Prune traversal below a discovered root (a nested repo inside another repo is NOT returned; the git-repo unit is the outermost `.git` boundary on each branch of the tree).
  - **Git repos only** — no project-marker fallback. "Git repo = the project unit" is the agreed intent; a caller who wants a non-git directory as a workspace opens it explicitly via `CodeContextManager.context(for:)` (or standalone `CodeContext`), which accepts any directory. This also keeps discovery symmetric with lazy routing (`gitRoot(containing:)`) and avoids a marker directory shadowing git repos nested beneath it.
  - Skip hidden directories and do not follow symlinks (mirror `Walker`'s policy), except the `.git` presence check on each visited directory.
  - Return roots as standardized file URLs, sorted by path for deterministic output.
- `public static func gitRoot(containing path: URL) -> URL?` — walk upward from `path` (or its parent if it's a file) to the nearest ancestor containing a `.git` entry; `nil` if none before the filesystem root. Standardize the returned URL.

## Acceptance Criteria
- [ ] `discoverRoots` finds sibling repos under a parent folder and returns them sorted
- [ ] A repo nested inside another repo's working tree is pruned (only the outer root returned)
- [ ] A `.git` *file* (worktree-style) is recognized as a root
- [ ] A directory with project markers but no `.git` is NOT returned (git repos only)
- [ ] Hidden directories and symlinks are not traversed
- [ ] `gitRoot(containing:)` resolves a deep file path to its enclosing repo root and returns nil outside any repo

## Tests
- [ ] `Tests/FoundationModelsCodeContextTests/RootDiscoveryTests.swift` using temp-dir fixtures built with FileManager (create `.git` dirs/files by hand; no real `git` needed): sibling repos, nested repo pruning, `.git`-file recognition, marker-only dir excluded, hidden/symlink skipping, `gitRoot` upward resolution and nil case
- [ ] `swift test --filter RootDiscoveryTests` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.