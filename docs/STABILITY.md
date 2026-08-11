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
- The widget repairs a missing native `WS_EX_TOPMOST` state after native window-position changes, Explorer restart, display changes, session unlock and power resume. Recovery uses `SWP_NOACTIVATE`, preserves geometry and never toggles `Topmost` off.
- Check the native state before repairing it. Do not poll or repeatedly push the widget ahead of other topmost applications.

## Persistence and diagnostics

- Settings and `status.json` are written to a sibling temporary file and atomically replaced.
- Settings validation clamps numeric values, repairs invalid enums, and replaces invalid or missing colors with defaults.
- Invalid settings are preserved as `settings.corrupt-YYYYMMDD-HHMMSS.json`; startup continues with defaults.
- Never clear `crash.log` at startup. It is append-only and rotates to `crash.previous.log` after 256 KiB.
- Diagnostics must never contain credentials, tokens, authorization headers, browser content, or Claude/Codex conversations.

## Update scheduling

- Automatic checks run only for installed Velopack builds and only while the user setting is enabled. Development and portable builds must not start the schedule.
- Schedule the next local wall-clock hour from the current time after every tick. Do not use a repeating one-hour interval that drifts from the clock boundary.
- Startup, hourly and manual checks share one in-flight update query. Automatic current, unavailable, offline and error results are silent; a manual request still receives the shared final result.
- Persist the last automatically notified version and suppress only repeated automatic notifications for that version. Manual checks are never suppressed.
- If resume or a system-time change crosses the saved boundary, run at most one catch-up check and then realign to the next hour. Duplicate lifecycle events must not produce notification bursts.
- Turning automatic checks off stops the timer immediately and must also suppress a notification from a query already in flight. `Dispose()` stops the timer and post-await continuations check `_disposed` before touching UI.

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
6. For update changes, separately test current, available, download cancel, download failure, apply/restart, startup and exact-hour checks, setting on/off, same-version deduplication, notification click, hidden-tray fallback, overlapping checks, offline behavior and sleep/time-change recovery from an installed Velopack build. A plain published EXE cannot prove the install/update path.
7. For widget lifecycle changes, test Win+L/unlock, sleep/resume, Explorer restart and display transitions; the foreground window, widget geometry and pointer interactions must remain unchanged during topmost repair.
