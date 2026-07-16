/// A language server's launch and lifecycle configuration.
///
/// Ports the Rust `builtin/lsp/*.yaml` server specs to a plain Swift value
/// declared directly by the owning `LanguageModule` — no standalone YAML
/// registry (see plan.md "LSP subsystem": "the Rust YAML spec fields become
/// a plain Swift value ... No standalone registry; the supervisor collects
/// specs from `Languages.all`."). Multi-language servers (e.g.
/// `typescript-language-server`, `clangd`) share one `ServerSpec` instance
/// across their modules; the supervisor dedupes daemons by `command`.
public struct ServerSpec: Sendable, Equatable {
    /// The executable to spawn, looked up on `$PATH` (e.g. `"rust-analyzer"`).
    public let command: String

    /// Arguments passed to `command` on launch.
    public let arguments: [String]

    /// LSP `languageId` values this server handles (e.g. `["rust"]`).
    public let languageIDs: [String]

    /// How long to wait for the `initialize`/`initialized` handshake before
    /// treating startup as failed.
    public let startupTimeout: Duration

    /// How often the supervisor checks that the daemon process is still
    /// alive.
    public let healthCheckInterval: Duration

    /// Human-readable guidance shown when `command` isn't found on `$PATH`.
    public let installHint: String

    /// A machine-actionable installer for `command`, or `nil` for hint-only
    /// behavior.
    ///
    /// When present, the supervisor may run `tool` with `arguments` to
    /// install `command` automatically before falling back to showing
    /// `installHint`. `nil` means today's behavior: no auto-install is
    /// attempted, and only `installHint` is shown.
    public let installer: InstallSpec?

    /// A machine-actionable installer: an executable plus the arguments that
    /// install a language server's `command`.
    public struct InstallSpec: Sendable, Equatable {
        /// The installer executable, looked up on `$PATH` (e.g. `"npm"`,
        /// `"rustup"`, `"go"`, `"pipx"`, `"brew"`). If `tool` itself is
        /// missing from `$PATH`, auto-install is skipped and the owning
        /// `ServerSpec.installHint` behavior stands.
        public let tool: String

        /// The full argv tail passed to `tool` (e.g.
        /// `["install", "-g", "typescript-language-server", "typescript"]`).
        public let arguments: [String]

        /// Well-known bin directories the install lands in that may not be
        /// on `$PATH`, with `~` expansion left to the use site (e.g.
        /// `["~/go/bin"]` for `go install`, `["~/.cargo/bin"]` for
        /// `rustup component add`). Empty when `tool` installs onto `$PATH`
        /// directly (e.g. `npm`, `brew`).
        public let extraSearchDirectories: [String]

        /// Creates an install spec.
        ///
        /// - Parameters:
        ///   - tool: The installer executable, looked up on `$PATH`.
        ///   - arguments: The full argv tail passed to `tool`. Defaults to
        ///     none.
        ///   - extraSearchDirectories: Well-known bin directories the
        ///     install lands in that may not be on `$PATH`. Defaults to
        ///     none.
        public init(
            tool: String,
            arguments: [String] = [],
            extraSearchDirectories: [String] = []
        ) {
            self.tool = tool
            self.arguments = arguments
            self.extraSearchDirectories = extraSearchDirectories
        }
    }

    /// Creates a server spec.
    ///
    /// - Parameters:
    ///   - command: The executable to spawn, looked up on `$PATH`.
    ///   - arguments: Arguments passed to `command` on launch. Defaults to none.
    ///   - languageIDs: LSP `languageId` values this server handles.
    ///   - startupTimeout: Handshake timeout. Defaults to 30 seconds, matching
    ///     every `builtin/lsp/*.yaml` spec's `startup_timeout_secs`.
    ///   - healthCheckInterval: Liveness check interval. Defaults to 60
    ///     seconds, matching every `builtin/lsp/*.yaml` spec's
    ///     `health_check_interval_secs`.
    ///   - installHint: Guidance shown when `command` isn't found on `$PATH`.
    ///   - installer: A machine-actionable installer for `command`. Defaults
    ///     to `nil` (hint-only, exactly today's behavior).
    public init(
        command: String,
        arguments: [String] = [],
        languageIDs: [String],
        startupTimeout: Duration = .seconds(30),
        healthCheckInterval: Duration = .seconds(60),
        installHint: String,
        installer: InstallSpec? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.languageIDs = languageIDs
        self.startupTimeout = startupTimeout
        self.healthCheckInterval = healthCheckInterval
        self.installHint = installHint
        self.installer = installer
    }
}
