# Dejavu stability contract

Use this checklist when changing lifecycle, refresh, authentication, updates, persistence, or diagnostics.

## Async ownership

- `_refreshGate` serializes provider refreshes. Periodic and login-watch refreshes coalesce; a user-forced refresh cancels the current request and waits for its gate.
- The method that creates a `CancellationTokenSource` owns and disposes it. `Dispose()` only cancels active sources; it must not dispose a source while its task is still unwinding.
- Provider readers must rethrow cancellation before translating other exceptions into a provider status.
- Do not use `Dispatcher.InvokeAsync(async () => ...)` without unwrapping the nested task. Tray-originated async actions go through `InvokeOnDispatcherAsync`.
- Every continuation that can outlive the app checks `_disposed` before updating WPF controls or application state.

## Window and process lifecycle

- Dejavu uses `ShutdownMode.OnExplicitShutdown`; closing settings or update windows normally hides them.
- During application exit, `AllowClose` must be set on windows that cancel `Closing`, then `Application.Shutdown()` may close them.
- Keep the named mutex and activation event behavior: a second process activates settings in the first process.
- Browser, Explorer, registry, and other shell operations may fail. UI event handlers must translate those failures into a visible status and must not crash the dispatcher.

## Persistence and diagnostics

- Settings and `status.json` are written to a sibling temporary file and atomically replaced.
- Settings validation clamps numeric values, repairs invalid enums, and replaces invalid or missing colors with defaults.
- Invalid settings are preserved as `settings.corrupt-YYYYMMDD-HHMMSS.json`; startup continues with defaults.
- Never clear `crash.log` at startup. It is append-only and rotates to `crash.previous.log` after 256 KiB.
- Diagnostics must never contain credentials, tokens, authorization headers, browser content, or Claude/Codex conversations.

## Claude non-interference

- Dejavu never injects into, hooks, suspends, kills, or sends window messages to Claude Desktop.
- Claude Desktop integration is read-only. Never write to or delete files under Claude's AppData or package directories.
- Copy `plan-usage-history.json` under a fully shared read handle, close it immediately, and parse the memory snapshot afterward.
- Cache a valid Desktop snapshot by file timestamp and length so unchanged history is not reopened every refresh.
- Copy Claude Code credentials to memory and close the file before JSON parsing or network access.
- Launching `claude://` or Claude Code authentication is allowed only after an explicit user action.
- When investigating a reported conflict, distinguish Claude `APPCRASH` from `MoAppHang`, correlate timestamps, and verify whether the WER report names Dejavu as a waiting or loaded process before claiming causation.

## Required verification

1. Parse every changed XAML file as XML.
2. Run `git diff --check`.
3. Run an isolated Release build.
4. Exercise the widget layout matrix described in `WIDGET_UI.md`.
5. Smoke-test first start, second-instance activation, settings/details open and close, forced refresh during an active refresh, and tray exit.
6. For update changes, separately test current, available, download cancel, download failure, and apply/restart from an installed Velopack build. A plain published EXE cannot prove the install/update path.
