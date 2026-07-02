---
depends_on:
- 01KWJ3QTH53M16194BCTX6MKVP
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: todo
position_ordinal: '9080'
title: 'FSEvents watcher: debounced change pipeline'
---
## What
Create `Sources/CodeContextKit/Index/Watcher.swift` — replaces Rust's notify/async-watcher with FSEvents (recursive on rootDirectory), ~1s debounce window, filtered to extensions in `Languages.all` and excluding gitignored paths and `.code-context/`. Coalesced events map to created/modified → mark dirty (all layers), deleted → DELETE row (cascades), then nudge the indexing workers. Debounce clock injectable; the FSEvents source wrapped behind a small `FileEventSource` protocol so tests can drive synthetic event streams without the real FS API.

## Acceptance Criteria
- [ ] A burst of N events on one file within the debounce window produces exactly one dirty-mark and one worker nudge
- [ ] Delete events remove the `indexed_files` row and cascaded children
- [ ] Events under gitignored paths and `.code-context/` are ignored

## Tests
- [ ] `Tests/CodeContextKitTests/WatcherTests.swift` driving a fake `FileEventSource` + manual clock: debounce coalescing, dirty/delete flows, filtering; one real-FSEvents integration test (temp dir, write a file, await dirty flag with generous timeout)
- [ ] Run `swift test --filter WatcherTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.