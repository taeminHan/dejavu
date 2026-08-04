# Dejavu architecture

This document is the project-level map for maintainers and coding agents. Read it before changing provider detection, authentication, application lifecycle, persistence, updates, or uninstall behavior. UI-specific contracts live in `WIDGET_UI.md`; lifecycle safety contracts live in `STABILITY.md`.

## Product boundary

Dejavu is a single-process Windows 11 WPF application that keeps a topmost usage widget visible, exposes settings and a detailed usage window, and owns a notification-area icon. It reads usage from local Claude and Codex installations and, where required, asks those official local clients to perform authentication. It does not host a server and does not store OAuth tokens.

The project intentionally depends on local and non-public integration surfaces. Keep each dependency isolated behind its provider client so a provider change does not spread into WPF windows.

## Runtime ownership

| Component | Responsibility |
|---|---|
| `Program.cs` | Velopack bootstrap, single-instance mutex, second-instance activation event, WPF application creation, global crash logging and preview argument parsing. |
| `DesktopApplicationController.cs` | Composition root. Owns windows, provider clients, timers, refresh serialization, tray actions, login flows, updates, startup registration and shutdown. |
| `ApplicationState.cs` | Immutable combined Claude/Codex state delivered to every view. |
| `ClaudeEnvironmentDetector.cs` | Finds Claude Code credentials and executables; launches official login or setup pages after a user action. |
| `ClaudeUsageClient.cs` | Reads a Claude Code credential snapshot, queries Anthropic usage, parses 5-hour, weekly and Fable limits, then falls back to Desktop history when login is unavailable. |
| `ClaudeDesktopUsageReader.cs` | Reads and caches recent `%AppData%\Claude\plan-usage-history.json` snapshots without holding Claude files open. |
| `CodexUsageClient.cs` | Finds a runnable Codex executable, starts its local `app-server`, reads rate limits and starts the official ChatGPT browser login. |
| `TraySettings.cs` | Settings schema, validation, legacy migration, atomic persistence and service-visibility policy. |
| `AppDiagnostics.cs` | Writes a credential-free status snapshot for support diagnostics. |
| `VelopackUpdateService.cs` | Checks GitHub Releases, downloads Velopack packages and applies an installed update. |
| `ThemeManager.cs` / `ThemeResources.xaml` | Semantic theme values and shared WPF control styles. |
| `WidgetLayoutCalculator.cs` | Pure source of truth for widget geometry. |
| `UsageWidgetWindow*` | Always-visible widget rendering, pointer interaction and monitor positioning. |
| `UsageDetailsWindow*` | Expanded usage values, reset credits and reset times. |
| `SettingsWindow*`, `OnboardingWindow*`, `UpdateWindow*` | Configuration, first-run connection guidance and update decisions. |

## Startup and shutdown

1. `Program.Main` registers Velopack callbacks. The uninstall callback removes Dejavu startup entries and local Dejavu data.
2. `Local\dejavu.SingleInstance` becomes the process owner. A second process signals `Local\dejavu.ShowSettings` and exits.
3. WPF starts with `ShutdownMode.OnExplicitShutdown`; closing settings and update windows hides them instead of ending the process.
4. `DesktopApplicationController` loads settings, applies theme resources, wires windows and timers, migrates old startup entries and begins provider refresh.
5. `Dispose` cancels owned asynchronous work, stops timers, hides windows and disposes tray resources. `Exit` then calls `Application.Shutdown()`.

Do not change this into close-on-last-window behavior. The widget and tray application must survive while auxiliary windows are hidden.

## Refresh and state flow

`DesktopApplicationController.RefreshAsync` is the only combined provider refresh entry point.

1. `_refreshGate` allows one refresh at a time.
2. Periodic refreshes coalesce. A forced user refresh cancels the active request and waits for the gate.
3. Claude and Codex reads run concurrently with a shared refresh cancellation token.
4. Provider exceptions are translated into independent `UsageStatus` values while the previous valid snapshot may remain available.
5. One `ApplicationState` updates the widget, details, settings connection state, onboarding, tray and credential-free diagnostics.

Views must not call provider clients directly or infer provider availability from current element visibility.

## Claude source selection

Claude source selection is deliberately asymmetric:

1. Unless `DEJAVU_CLAUDE_SOURCE=desktop`, locate a non-empty credential file in `CLAUDE_CONFIG_DIR\.credentials.json` or `%UserProfile%\.claude\.credentials.json`.
2. Copy the credential file to memory under `FileShare.ReadWrite | FileShare.Delete`, close it, then parse the OAuth access token.
3. Query `https://api.anthropic.com/api/oauth/usage`. This is used by Claude Code but is not a documented third-party API contract.
4. Parse session, weekly-all and scoped Fable limits. Legacy response names remain supported for compatibility.
5. If credentials are missing, expired, unauthorized or malformed, try a recent Claude Desktop history snapshot.
6. Desktop history is accepted only when its captured time is recent. It supplies 5-hour and weekly percentages but not Fable or reset timestamps.

Claude Code executable discovery checks `CLAUDE_CODE_PATH`, common native/npm paths, Claude Desktop bundled Claude Code, then `PATH`. Login is launched only from an explicit user action. Never write to or delete Claude files.

## Codex source selection

Codex does not read ChatGPT credentials directly.

1. Use `CODEX_CLI_PATH` when it points to a runnable native executable.
2. Unless `DEJAVU_CODEX_SOURCE=desktop`, inspect npm/nvm and `PATH` locations for the native Codex executable. Protected WindowsApps aliases are excluded.
3. Fall back to `%LocalAppData%\OpenAI\Codex\bin` candidates bundled with Codex Desktop.
4. Start `<codex executable> app-server` without a window and exchange newline-delimited JSON messages over standard input/output.
5. Initialize the client and call `account/rateLimits/read`; parse 5-hour, weekly, plan and reset-credit information.
6. For login, call `account/login/start` with `type=chatgpt`, open the returned official browser URL and wait for `account/login/completed`.
7. Kill only the child `app-server` process that Dejavu started. Never terminate the Codex Desktop application.

If no runnable executable exists, the UI links to the official Codex Windows installation page.

## Local persistence

| Path or registry value | Contents and policy |
|---|---|
| `%LocalAppData%\dejavu\settings.json` | User settings. Written through `settings.json.tmp` and atomically replaced. |
| `%LocalAppData%\dejavu\settings.corrupt-*.json` | Preserved invalid settings. Startup continues with normalized defaults. |
| `%LocalAppData%\dejavu\status.json` | Support status, percentages, timestamps, geometry and source availability. Must never contain tokens or conversations. |
| `%LocalAppData%\dejavu\crash.log` | Append-only crash details. Rotates to `crash.previous.log` above 256 KiB. |
| `%LocalAppData%\ClaudeUsageTray\settings.json` | Legacy settings source migrated on load. |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\dejavu` | Optional current-user startup entry. Legacy `UsageBarForClaude` and `ClaudeUsageTray` entries are removed during migration. |

Velopack uninstall removes the startup entries plus `%LocalAppData%\dejavu` and `%LocalAppData%\ClaudeUsageTray`. It must not remove Claude, Codex or browser data.

## Updates and releases

Installed builds use `VelopackUpdateService`; plain `dotnet run`, build output and portable executables are not considered installed and cannot prove update behavior. Release-candidate builds include prereleases when querying `taeminHan/dejavu` GitHub Releases.

The tag workflow in `.github/workflows/release.yml` installs Velopack CLI, downloads the previous package for delta generation, calls `tools/BuildRelease.ps1`, publishes the GitHub Release and uploads the stable `dejavu-Setup.exe` alias plus checksums.

## Extension rules

### Add a provider

Create a provider-specific snapshot, client and exceptions; translate them in the controller; extend `ApplicationState`; then update service resolution, diagnostics, onboarding, settings, widget/details state matrices and privacy documentation. Do not put authentication or HTTP/process code in a window.

### Add a metric

Add it to the provider snapshot, parse it once, clamp its percentage at the display boundary, and feed the same value to text and progress geometry. Decide explicitly whether it belongs in the always-visible widget or details only, then update `WIDGET_UI.md`.

### Add or modify a theme

Put semantic resources and reusable styles in `ThemeResources.xaml`, palette/capability decisions in `ThemeManager.cs`, and only truly structural window behavior in code-behind. Validate every density, layout and service combination.

## Known boundaries

- Claude usage integration is not a public third-party API contract and may change without notice.
- Claude Desktop history cannot provide Fable or reset times when Claude Code authentication is unavailable.
- Codex requires a runnable Codex Desktop bundled binary or native CLI.
- The Windows taskbar has no supported API for arbitrary third-party usage text; Dejavu remains a separate topmost widget.
- A successful compile is not visual validation, and a portable executable is not an update/install validation.
