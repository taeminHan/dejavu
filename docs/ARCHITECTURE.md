# Dejavu architecture

This document is the Windows project-level map for maintainers and coding agents. Read it before changing provider detection, authentication, application lifecycle, persistence, updates, or uninstall behavior. UI-specific contracts live in `WIDGET_UI.md`; lifecycle safety contracts live in `STABILITY.md`; proposed cross-platform work lives in `MACOS_SUPPORT_PLAN.md`.

## Product boundary

Dejavu is a single-process Windows 11 WPF application that keeps a topmost usage widget visible, exposes settings and a detailed usage window, and owns a notification-area icon. It reads usage from local Claude and Codex installations and, where required, asks those official local clients to perform authentication. It does not host a server and does not store OAuth tokens.

The project intentionally depends on local and non-public integration surfaces. Keep each dependency isolated behind its provider client so a provider change does not spread into WPF windows.

## Runtime ownership

| Component | Responsibility |
|---|---|
| `Program.cs` | Velopack bootstrap, single-instance mutex, second-instance activation event, WPF application creation, global crash logging and preview argument parsing. |
| `DesktopApplicationController.cs` | Composition root. Owns windows, provider clients, timers, refresh serialization, tray actions, login flows, updates, startup registration, taskbar tracking and shutdown. |
| `ApplicationState.cs` | Immutable combined Claude/Codex state delivered to every view. |
| `ClaudeEnvironmentDetector.cs` | Finds Claude Code credentials and executables; launches official login or setup pages after a user action. |
| `ClaudeUsageClient.cs` | Reads a Claude Code credential snapshot, queries Anthropic usage, parses 5-hour, weekly and Fable limits, then falls back to Desktop history when login is unavailable. |
| `ClaudeDesktopUsageReader.cs` | Reads and caches recent `%AppData%\Claude\plan-usage-history.json` snapshots without holding Claude files open. |
| `CodexUsageClient.cs` | Finds a runnable Codex executable, starts its local `app-server`, reads rate limits and starts the official ChatGPT browser login. |
| `TraySettings.cs` | Settings schema, validation, legacy migration, atomic persistence and service-visibility policy. |
| `AppDiagnostics.cs` | Writes a credential-free status snapshot for support diagnostics. |
| `VelopackUpdateService.cs` | Checks GitHub Releases, downloads Velopack packages and applies an installed update. |
| `ThemeManager.cs` / `ThemeResources.xaml` | Semantic theme values and shared WPF control styles. |
| `WidgetLayoutCalculator.cs` | Pure source of truth for widget geometry, including the in-taskbar branch (`TaskbarLayoutMetrics`). |
| `TaskbarTracker.cs` | Enabled only for `WidgetPlacement.InTaskbar`. Finds the primary Windows 11 taskbar band with message-free local reads, listens for `TaskbarCreated`, display and setting broadcasts plus an out-of-context foreground WinEvent hook, and reports `Docked`, `Suppressed` or `Fallback` with a device-pixel `TaskbarDock`. It never modifies, parents or owns Explorer windows and sends them no window messages of its own. Its only call into Explorer is the `SHAppBarMessage(ABM_GETSTATE)` auto-hide query (shell32 delivers it as a synchronous `WM_COPYDATA` to `Shell_TrayWnd`), which runs on a single thread-pool worker with a 2 s timeout on enable, every settle, `WM_SETTINGCHANGE` and every 15 s. |
| `UsageWidgetWindow*` | Always-visible widget rendering, pointer interaction, DPI-correct monitor positioning, the docked taskbar look and anchor, native topmost-band recovery and the scoped raise above a covering taskbar. |
| `UsageDetailsWindow*` | Expanded usage values, reset credits and reset times. |
| `SettingsWindow*`, `OnboardingWindow*`, `UpdateWindow*` | Configuration, first-run connection guidance and update decisions. |

## Startup and shutdown

1. `Program.Main` registers Velopack callbacks. The uninstall callback removes Dejavu startup entries and local Dejavu data.
2. `Local\dejavu.SingleInstance` becomes the process owner. A second process signals `Local\dejavu.ShowSettings` and exits.
3. WPF starts with `ShutdownMode.OnExplicitShutdown`; closing settings and update windows hides them instead of ending the process.
4. `DesktopApplicationController` loads settings, applies theme resources, wires windows and timers, migrates old startup entries and begins provider refresh.
5. `Dispose` cancels owned asynchronous work, stops timers, unsubscribes `SystemEvents`, disposes `TaskbarTracker` (unhooking its WinEvent hook and hidden window), hides windows and disposes tray resources. `Exit` then calls `Application.Shutdown()`.

Do not change this into close-on-last-window behavior. The widget and tray application must survive while auxiliary windows are hidden.

## Refresh and state flow

`DesktopApplicationController.RefreshAsync` is the only combined provider refresh entry point.

1. `_refreshGate` allows one refresh at a time.
2. Periodic refreshes coalesce. A forced user refresh cancels the active request and waits for the gate; forced refreshes that are already waiting collapse into the newest one, so repeated clicks run one refresh and one Codex `app-server`.
3. Claude and Codex reads run concurrently with a shared refresh cancellation token. The Claude login watch runs Claude-only refreshes (`includeCodex: false`) that carry the last settled Codex values unchanged, unless Codex has never been checked. While Codex is visible, such a refresh keeps the previous `UpdatedAt`, so the "마지막 확인" time never advances past the last Codex read.
4. Before the reads, `ApplicationState.Loading(previous)` is applied. It keeps each provider's last settled status, message, snapshot and `UpdatedAt`; only the overall `Status == Loading` marks the refresh in flight. A provider status of `Loading` therefore means that provider has never been checked, and views must not treat a refresh as a lost connection.
5. Provider exceptions are translated into independent `UsageStatus` values while the previous valid snapshot may remain available. A carried snapshot never keeps a limit whose `ResetsAt` has passed, nor Claude Desktop values older than the Desktop recency window: those limits become `null` (`--%`) while the snapshot object, and so the automatic-detection slot, stays. A carried Claude Code Fable limit cleared this way sets `UsageSnapshot.FableExpired`, so it reads `--%` rather than "not provided". A carried Codex weekly limit cleared this way sets `CodexUsageSnapshot.WeeklyExpired`, so the widget and tray value (`DisplayLimit`) reads `--%` instead of falling back to the 5-hour window, which is reserved for accounts without a weekly window. A cancelled refresh applies no state.
6. One `ApplicationState` updates the widget, details, settings connection state, onboarding, tray and credential-free diagnostics.
7. The periodic interval is normally `RefreshSeconds`. After a full refresh in which a provider failed transiently (network, timeout, server or read error), the next two refreshes come after 10 s and then 30 s; the streak gets no more early retries until a refresh without a transient failure. Rate limits, login states and a missing Codex CLI never retry early; a Claude rate limit instead schedules the next full refresh just after `RetryAt` when that is sooner than the interval, and a `429` from a Claude-only login-watch refresh may bring the periodic refresh forward the same way but never pushes it back. A settings save may bring the next refresh forward (a shorter interval or the `RetryAt` cap) but never pushes back a pending early retry or nudge. Power resume, session unlock/logon and, while a provider is `Offline` or `Error`, a network-availability change move the next periodic refresh 5 s ahead instead of refreshing directly, so it still coalesces and never cancels a Codex read.
8. A Claude `429` records `Retry-After` (delta or HTTP date, clamped to 60 s–30 min) as `RetryAt`. Until then, periodic and login-watch refreshes make no Claude request and carry the previous values as `RateLimited`, unless the credential file's write time or length changed (a new login or token refresh); an explicit 지금 새로고침 still tries once, while the Codex-login follow-up forced refresh honors `RetryAt`. The wait runs on `Environment.TickCount64`, so a system-clock change neither stretches nor shortens it; `RetryAt` is expressed in the current clock from the remaining time whenever the state is built. The details footer shows the retry time while Claude is visible.

Views must not call provider clients directly or infer provider availability from current element visibility.

## Claude source selection

Claude source selection is deliberately asymmetric:

1. Unless `DEJAVU_CLAUDE_SOURCE=desktop`, locate a non-empty credential file in `CLAUDE_CONFIG_DIR\.credentials.json` or `%UserProfile%\.claude\.credentials.json`.
2. Copy the credential file to memory under `FileShare.ReadWrite | FileShare.Delete`, close it, then parse the OAuth access token.
3. Query `https://api.anthropic.com/api/oauth/usage`. This is used by Claude Code but is not a documented third-party API contract.
4. Parse session, weekly-all and scoped Fable limits. Legacy response names remain supported for compatibility.
5. If credentials are missing, expired, unauthorized or malformed, try a recent Claude Desktop history snapshot. Without one, the outcome is classified as follows (`ReadClaudeAsync`):

   | Outcome | Provider status, message and `ClaudeIssue` |
   |---|---|
   | Access token expired and a refresh token is present (only its presence is checked; `refreshTokenExpiresAt`, when present, must be in the future) | `Error`, `Claude 토큰 갱신 대기`, `TokenRefreshPending`. Claude Code renews the token the next time it runs; Dejavu never refreshes or writes it. |
   | No credential file, and Desktop history exists without a recent sample (Desktop closed or idle) | `Error`, `Claude Desktop 기록 대기`, `DesktopHistoryStale` |
   | No credential file and no Desktop history; or malformed credentials, an expired token without a refresh token, or HTTP 401/403 | `LoginRequired`, `Claude 로그인 필요` |
   | HTTP 429 | `RateLimited`, `Claude 자동 재시도`, with `RetryAt` (see refresh step 8) |
   | Connection failure without a status code | `Offline`, `Claude 오프라인` |
   | 12 s `HttpClient` timeout (headers and the buffered body) | `Offline`, `Claude 응답 지연` |
   | HTTP 5xx/529 | `Error`, `Claude 서버 오류` |
   | Other non-success status (the endpoint changed) | `Error`, `Claude 사용량 응답 변경` |
   | Any other failure, for example a partial credential read | `Error`, `Claude 확인 실패` |

   Only `LoginRequired` is presented as a login problem. `ClaudeIssue` is a non-positional `ApplicationState` property, so the 10-parameter constructor the layout probe reflects is unchanged.
6. Desktop history is accepted only when its captured time is within 40 minutes (`ClaudeDesktopUsageReader.MaximumSampleAge`); Desktop writes a sample about every 15 minutes while it runs, often a little late, so a shorter window flips a running Desktop between available and stale. It supplies 5-hour and weekly percentages but not Fable or reset timestamps, and the provider message names the sample time (`Claude Desktop 기록 HH:mm`).

Claude Code executable discovery checks `CLAUDE_CODE_PATH`, common native/npm paths, Claude Desktop bundled Claude Code, then `PATH`. Login is launched only from an explicit user action. Never write to or delete Claude files.

## Codex source selection

Codex does not read ChatGPT credentials directly.

1. Use `CODEX_CLI_PATH` when it points to a runnable native executable.
2. Unless `DEJAVU_CODEX_SOURCE=desktop`, inspect npm/nvm and `PATH` locations for the native Codex executable. Protected WindowsApps aliases are excluded.
3. Fall back to `%LocalAppData%\OpenAI\Codex\bin` candidates bundled with Codex Desktop.
4. Start `<codex executable> app-server` without a window and exchange newline-delimited JSON messages over standard input/output. Standard error is drained and discarded so verbose `RUST_LOG` output cannot fill the pipe and stall the child; it is never logged.
5. Initialize the client and call `account/rateLimits/read`; parse 5-hour, weekly, plan and reset-credit information from the `codex` bucket of `rateLimitsByLimitId`, falling back to `rateLimits`. Optional fields that arrive as JSON `null` are skipped instead of failing the read. Outcomes are classified as follows; JSON-RPC error messages are never logged or displayed:

   | Outcome | Exception | Provider status and message |
   |---|---|---|
   | `-32600` for missing or non-ChatGPT auth (not a protocol rejection such as `Invalid request…`, `Not initialized`, `Already initialized`, `Server is draining…` or `…requires experimentalApi capability`), or `-32603` whose message names a backend `401 Unauthorized` | `CodexLoginRequiredException` | `LoginRequired`, `Codex 로그인 필요` |
   | Other `-32603` (network or backend failure; upstream returns it only after it found ChatGPT auth) | `CodexBackendFailedException` | `Error`, `Codex 확인 실패 · 자동 재시도` |
   | Other JSON-RPC error (`-32001` overload, a `-32600` protocol rejection from an older or newer CLI), early exit, missing `result`, start or pipe failure | `CodexReadFailedException` or the generic catch | `Error`, `Codex 확인 실패 · 자동 재시도` |
   | No response within 15 s | `CodexTimeoutException` | `Offline`, `Codex 응답 지연 · 자동 재시도` |
   | No runnable executable, or `Process.Start` returns nothing | `CodexCliUnavailableException` | `Error`, `Codex CLI 필요` |
   | Refresh cancelled by a forced refresh or shutdown | `OperationCanceledException` is rethrown | No state is applied |

   Only a read settles `LoginRequired`. After it, the transient outcomes (read failure, timeout) keep `LoginRequired` until a successful read, and a failed login keeps it too; a transient failure is not evidence of a login. The exception is a `-32603` backend failure after a `LoginRequired` that came from a missing account (`-32600`): it proves ChatGPT auth is present, for example after a login made outside Dejavu, so it reports `Error` instead. A `LoginRequired` that came from a backend `401 Unauthorized` stays sticky through backend failures. A completed Dejavu login clears it (provider `Loading`, `Codex 확인 중`) before the follow-up forced refresh, so that read decides again; a failure before any successful read, whose card offered login as a fallback, is cleared the same way. A failed, abandoned or timed-out login never downgrades a `Ready` status that a read reported while the login was pending, and turns any status other than `LoginRequired` into `Error` rather than `LoginRequired`. Only the 15 s timeout kills the child through a token registration, because a pending read on a redirected pipe may not observe the token on Windows. A forced refresh or shutdown lets the pending read finish or time out first, so a child in the middle of an in-band OAuth token refresh can persist the rotated token before it is killed.
6. For login, call `account/login/start` with `type=chatgpt`, open the returned official browser URL and wait for `account/login/completed`. The 5-minute login timeout and shutdown kill the login child through a token registration, so a pending browser login always ends. While it is pending, the login buttons stay enabled as `브라우저 다시 열기` and a repeated login request reopens the same URL; it starts no second login child, and the URL is never logged or displayed. Once the login completes, the spent URL is cleared and the buttons return to their state label before the follow-up refresh.
7. Kill only the child `app-server` process that Dejavu started. Never terminate the Codex Desktop application.

If no runnable executable exists, the UI links to the official Codex Windows installation page.

## Local persistence

| Path or registry value | Contents and policy |
|---|---|
| `%LocalAppData%\dejavu\settings.json` | User settings, including the last automatically notified update version. Enums such as `WidgetPlacement` are stored as integers and are append-only. Written through `settings.json.tmp` and atomically replaced. Never stores provider credentials. |
| `%LocalAppData%\dejavu\settings.corrupt-*.json` | Preserved invalid settings. Startup continues with normalized defaults. |
| `%LocalAppData%\dejavu\status.json` | Support status, per-provider status and fixed Dejavu status messages (`claudeStatus`, `codexStatus`, `claudeMessage`, `codexMessage`, `claudeIssue`), the Claude rate-limit `retryAt`, percentages, timestamps, geometry, source availability, placement, taskbar tracker state and raise counters. Must never contain tokens, provider error text, conversations, or titles/classes of other processes' windows. |
| `%LocalAppData%\dejavu\crash.log` | Append-only crash details. Rotates to `crash.previous.log` above 256 KiB. |
| `%LocalAppData%\ClaudeUsageTray\settings.json` | Legacy settings source migrated on load. |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\dejavu` | Optional current-user startup entry. Legacy `UsageBarForClaude` and `ClaudeUsageTray` entries are removed during migration. |

Velopack uninstall removes the startup entries plus `%LocalAppData%\dejavu` and `%LocalAppData%\ClaudeUsageTray`. It must not remove Claude, Codex or browser data.

## Updates and releases

Installed builds use `VelopackUpdateService`; plain `dotnet run`, build output and portable executables are not considered installed and cannot prove update behavior. Release-candidate builds include prereleases when querying `taeminHan/dejavu` GitHub Releases.

When automatic checks are enabled, an installed build checks after startup and at the next local wall-clock hour. Every tick recalculates the following clock-hour boundary instead of adding a fixed interval, so delayed ticks do not drift. Resume and system-time changes perform at most one overdue check and then realign the schedule. Startup, hourly and manual requests share one in-flight query, which Dejavu abandons as an error after 60 s; automatic failures stay silent, the same version is notified only once across restarts, and manual checks always remain available. Disabling the setting stops the schedule immediately.

A failed check keeps an update that was already found; only a definitive current or not-installed result withdraws it, and the Settings button, notification click or install button then re-checks and shows the answer. While a download runs, no update query is made: automatic checks skip, and manual checks report the downloading release and only bring its window forward. The download captures its release once, re-arms a 10-minute stall watchdog on every progress report and can be cancelled with 취소, the close button or Alt+F4. After the download, `WaitExitThenApplyUpdates` starts the updater and Dejavu exits normally (tray icon removal, mutex release) before the updater applies the release and restarts it.

The tag workflow in `.github/workflows/release.yml` treats the Windows project version as the shared product version, builds the Windows Velopack and free ad-hoc macOS/Sparkle assets in separate runners, and publishes one GitHub Release only after both sets pass validation. It downloads the previous Windows package for delta generation, calls `tools/BuildRelease.ps1` and `tools/BuildMacFreeRelease.sh`, then uploads the stable `dejavu-Setup.exe` alias, macOS DMG/ZIP/appcast and checksums.

## Taskbar docking boundary

`InTaskbar` places Dejavu's own topmost widget window over the primary taskbar band; the window is never a child or owned window of Explorer.

1. `DesktopApplicationController.SyncTaskbarTracking` enables the tracker only while the widget is requested and the placement is `InTaskbar`, then applies the tracker state: `Docked` passes the dock to `UsageWidgetWindow.SetTaskbarDock`, `Suppressed` hides the widget, `Fallback` clears the dock and places the widget with the `TaskbarRight` formula, and `Inactive` (another placement is selected, or the widget is not requested) clears the dock so the selected placement's normal rules apply and a `Custom` top-left point is kept. The saved placement never changes.
2. `TaskbarTracker` evaluates on its timer, its hidden broadcast window and its foreground hook. It detects shell mismatch, non-XAML (Windows 10, ExplorerPatcher, StartAllBack), vertical, auto-hide, mirrored, too-small and missing taskbar/tray states, fullscreen and geometry settling.
3. `RaiseRequested` asks the widget to verify it is still above the taskbar; the widget reorders only itself and only when covered.

Explorer and registry failures must degrade to `Fallback` or `Suppressed`, and a failed raise is only recorded (`LastTaskbarRaiseError`); none may throw on the dispatcher. `docs/STABILITY.md` lists the permitted Win32 calls and the hook lifetime.

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
- The Windows taskbar has no supported API for arbitrary third-party usage text. Dejavu remains a separate topmost widget; `InTaskbar` overlays that widget on the taskbar band instead of embedding it.
- `InTaskbar` supports only the primary horizontal Windows 11 XAML taskbar. It is covered while Start, Search, Quick Settings or Notification Center is open, can drop behind the taskbar briefly after a taskbar click, and may overlap task buttons on a crowded taskbar because v1 does not measure free space.
- A successful compile is not visual validation, and a portable executable is not an update/install validation.
