---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxnd3w88kpe6t3eq3zhqtjrn
  text: |-
    Implemented via TDD:
    - Added `ServerSpec.InstallSpec` (tool/arguments/extraSearchDirectories) and `ServerSpec.installer: InstallSpec?` (defaults nil, existing constructions unchanged).
    - Populated installers: rust-analyzer (rustup component add, ~/.cargo/bin), typescript-language-server family (npm install -g, shared TS/TSX/JS), intelephense (npm install -g), gopls (go install golang.org/x/tools/gopls@latest, ~/go/bin — also fixed wrong module path in installHint), pylsp (pipx install, ~/.local/bin — also fixed installHint from pip to pipx), jdtls (brew install, also updated installHint to mention brew).
    - Verified omnisharp has no dependable Homebrew formula (only third-party OmniSharp/homebrew-omnisharp-roslyn tap, depends on mono, has open install-failure issues) — left installer nil per task instructions, documented in CSharp.swift doc comment.
    - sourcekit-lsp and clangd left installer nil (Xcode/CLT-bundled), unchanged.
    - New test file Tests/FoundationModelsCodeContextTests/InstallSpecTests.swift (14 tests) covers all tool/argument/extraSearchDirectories values, the nil cases, and installHint/tool agreement.
    - `swift build` exit 0, no new warnings. `swift test`: 499 tests in 42 suites passing.
    - Sent for adversarial double-check via really-done before handoff.
  timestamp: 2026-07-16T12:06:11.464328+00:00
- actor: claude-code
  id: 01kxne0vejkqpza3dnzf8ybvj9
  text: 'Adversarial double-check (double-check agent) returned PASS: diff scope matches spec exactly, ServerSpec init backward-compatible, every populated installer/installHint pair verified by direct read, nil cases (omnisharp/sourcekit-lsp/clangd) correct, CLI argument arrays correct. One stylistic nit noted (force-unwraps in the cross-check test loop would crash rather than fail on regression) — fixed by switching to guard-let on the optional `languageServer` before unwrapping `installer`. Re-ran full `swift test` after the fix: 499 tests, 42 suites, all passing, exit 0. Task is green and left in doing for /review.'
  timestamp: 2026-07-16T12:22:00.914974+00:00
- actor: claude-code
  id: 01kxng2s9rv8vkk57dgsgq49k5
  text: |-
    Pulled back from review to doing to address review finding: ServerSpec.args (an abbreviation) renamed to ServerSpec.arguments for consistency with the same-file InstallSpec.arguments naming.

    Changes:
    - Sources/FoundationModelsCodeContext/Languages/ServerSpec.swift: property, doc comment, init parameter, and self-assignment renamed args -> arguments.
    - Sources/FoundationModelsCodeContext/Languages/SharedServerSpecs.swift: typescript-language-server spec's args: ["--stdio"] -> arguments: ["--stdio"].
    - Sources/FoundationModelsCodeContext/Languages/PHP.swift: intelephense spec's args: ["--stdio"] -> arguments: ["--stdio"].
    - Sources/FoundationModelsCodeContext/LSP/LSPDaemon.swift: doc comment and processConnectionFactory's arguments: spec.args -> spec.arguments.
    - Tests/FoundationModelsCodeContextTests/LiveSourceKitTests.swift: matching doc comment and call site updated to spec.arguments.
    - Tests/FoundationModelsCodeContextTests/LanguageModuleTests.swift: #expect(spec.args.isEmpty) -> #expect(spec.arguments.isEmpty).

    Rust.swift, Go.swift, Python.swift, Java.swift, CSharp.swift, Swift.swift needed no changes: none of their ServerSpec(...) constructions pass args: explicitly (they rely on the default [] or have no launch arguments).

    Verified: swift build exit 0 (no new warnings, only pre-existing unrelated mlx-swift bundle warning), swift test: 499 tests, 42 suites, all passing, exit 0. Grep confirms no remaining references to the old ServerSpec.args name in Sources/ or Tests/ (only unrelated <args> doc placeholders in DiagnosticsScope.swift referring to generic CLI argv). Sent for adversarial double-check via really-done before handoff.
  timestamp: 2026-07-16T12:58:01.400812+00:00
- actor: claude-code
  id: 01kxng9rgsfn9njs7e9hrn1300
  text: |-
    Adversarial double-check (double-check agent, via really-done) returned PASS: confirmed via `git diff --stat` that exactly the expected files changed, every hunk is a pure 1:1 args->arguments substitution with no reordering/default/value changes, exhaustive grep across Sources/ and Tests/ found zero leftover ServerSpec.args references (only unrelated <args> CLI-shape doc placeholders in DiagnosticsScope.swift), and directly read Rust/Go/Python/Java/CSharp/Swift/C/CPP/TypeScript/JavaScript/TSX modules to confirm none construct ServerSpec with an args:/arguments: label needing a fix. Independently re-ran swift build (exit 0) and swift test (499 tests, 42 suites, exit 0).

    Checked off the review finding on the task. Task remains in doing, green, ready for re-review.
  timestamp: 2026-07-16T13:01:49.977416+00:00
position_column: done
position_ordinal: ae80
title: Add InstallSpec to ServerSpec and populate per-language install commands
---
## What
Give `ServerSpec` a machine-actionable installer alongside the existing human `installHint`.

- `Sources/FoundationModelsCodeContext/Languages/ServerSpec.swift`: add `public struct InstallSpec: Sendable, Equatable` with:
  - `tool: String` — the installer executable, looked up on `$PATH` (e.g. `"npm"`, `"rustup"`, `"go"`, `"pipx"`, `"brew"`); if the tool itself is missing, auto-install is skipped and the existing hint behavior stands.
  - `arguments: [String]` — full argv tail (e.g. `["install", "-g", "typescript-language-server", "typescript"]`).
  - `extraSearchDirectories: [String]` — well-known bin dirs the install lands in that may not be on `$PATH`, with `~` expansion at use site (e.g. `["~/go/bin"]` for go, `["~/.cargo/bin"]` for rustup). Empty when the tool installs onto `$PATH` (npm, brew).
  - Add `public let installer: InstallSpec?` to `ServerSpec` with a `nil` default in the init — `nil` means hint-only, exactly today's behavior. Existing spec constructions compile unchanged.
- Populate installers in the language modules (`Sources/FoundationModelsCodeContext/Languages/SharedServerSpecs.swift` and/or the per-language files where each `languageServer` is declared):
  - rust-analyzer → `rustup component add rust-analyzer`, extra dir `~/.cargo/bin`
  - typescript-language-server → `npm install -g typescript-language-server typescript`
  - intelephense (PHP.swift) → `npm install -g intelephense` (npm-installable exactly like typescript-language-server)
  - gopls → `go install golang.org/x/tools/gopls@latest`, extra dir `~/go/bin`
  - pylsp → `pipx install python-lsp-server` (pipx, not pip: avoids PEP 668 externally-managed-environment failures), extra dir `~/.local/bin`
  - jdtls → `brew install jdtls`
  - omnisharp → verify at implementation time whether a reliable Homebrew formula exists; if none does, leave `installer: nil` (graceful hint-only degradation is the correct behavior for any server without a dependable install command)
  - sourcekit-lsp, clangd → `installer: nil` (Xcode/CLT-bundled; not installable by us)
- **Align every `installHint` string with its installer command** — they must not contradict. Known drift to fix: `Go.swift`'s hint uses the wrong module path (`github.com/golang/tools/gopls` → correct is `golang.org/x/tools/gopls@latest`); `Python.swift`'s hint says `pip install python-lsp-server` while the installer uses pipx.

Note: this touches ServerSpec.swift plus ~7 one-line per-language module edits and a test file — over the usual file-count guideline but a single concern with trivial per-file edits; do not split.

## Acceptance Criteria
- [ ] `ServerSpec.installer` exists, defaults to nil, and all existing code/tests compile unchanged
- [ ] Every install command above (including intelephense) is captured on the right module's spec with the right extra search dirs
- [ ] Xcode-bundled servers and any server without a dependable installer remain `installer: nil`
- [ ] Every `installHint` string agrees with its module's installer command (Go module path corrected; Python hint says pipx)

## Tests
- [ ] Extend the existing language-module/spec tests (or add `Tests/FoundationModelsCodeContextTests/InstallSpecTests.swift`): assert each named server's `installer` tool/arguments/extraSearchDirectories (including intelephense), that sourcekit-lsp/clangd have none, and that each populated module's `installHint` mentions the same tool as its installer
- [ ] `swift test` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-16 07:24)

- [x] `Sources/FoundationModelsCodeContext/Languages/ServerSpec.swift:15` — `args` is an abbreviation for `arguments`; the naming-clarity rule requires clarity over brevity and prohibits abbreviations. The new `InstallSpec` struct in the same file uses the full word `arguments` for the same semantic purpose, creating an inconsistency in naming within the file. Rename the property to `arguments` to align with the naming convention used in the new `InstallSpec` and to follow the clarity-over-brevity principle.
