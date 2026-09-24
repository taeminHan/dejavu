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
- The always-visible widget cancels every close request (Alt+F4, an external `WM_CLOSE`) and stays visible, because the controller shows the same instance again and `Show()` on a closed WPF window throws. The controller also skips visibility changes once the widget has closed.
- During application exit, `AllowClose` must be set on windows that cancel `Closing`, then `Application.Shutdown()` may close them.
- Keep the named mutex and activation event behavior: a second process activates settings in the first process.
- Browser, Explorer, registry, and other shell operations may fail. UI event handlers must translate those failures into a visible status and must not crash the dispatcher.
- The widget repairs a missing native `WS_EX_TOPMOST` state after native window-position changes, Explorer restart, display changes, session unlock and power resume. Recovery uses `SWP_NOACTIVATE`, preserves geometry and never toggles `Topmost` off.
- Check the native state before repairing it. Do not poll or repeatedly push the widget ahead of other topmost applications.
- Single scoped exception: while the in-taskbar placement is enabled, `TaskbarTracker` runs a 1 s `DispatcherTimer` backstop (250 ms while settling) whose dispatcher work is limited to message-free local reads (every 15 s it also re-queues the thread-pool `SHAppBarMessage(ABM_GETSTATE)` query described below), and the widget raises itself only when `Shell_TrayWnd` covers it. The raise inserts the widget directly above the taskbar with `SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER`, at most once per 250 ms and 60 times per rolling minute. When a raise leaves it covered (Start or a system flyout), the backstop stops raising until the foreground window changes; foreground requests, their +300/+600 ms follow-ups and the controller's `docked` check may still try once each. It never activates the widget, changes its geometry, or moves it above windows that are already above the taskbar. While the tracker is disabled no such timer, hook or raise exists.

## Explorer and taskbar non-interference

- Never use `SetParent`, `GWLP_HWNDPARENT` or `WindowInteropHelper.Owner = Shell_TrayWnd`, `AttachThreadInput`, DLL injection, `SetWindowBand`, uiAccess, `SendMessage`/`PostMessage` to Explorer windows, or `GetWindowText` of another process's window. Any of these would tie Explorer's input or rendering to Dejavu.
- Window queries on the dispatcher thread are limited to message-free local reads: `FindWindowW`, `FindWindowExW`, `IsWindow`, `GetWindowRect`, `GetClientRect`, `ClientToScreen`, `GetWindowLongPtrW`, `GetWindow`, `GetClassNameW`, `IsZoomed`, `GetForegroundWindow`, `GetShellWindow`, `GetWindowThreadProcessId`, `MonitorFromWindow`, `GetMonitorInfoW`, `GetDpiForSystem`, `SystemParametersInfoW(SPI_GETHIGHCONTRAST)`, `QueryUnbiasedInterruptTime` and registry reads. `TaskbarTracker` compares `Environment.TickCount64` with `QueryUnbiasedInterruptTime`, which stops during sleep, and settles again on the first evaluation after the PC slept, before the controller's resume notification arrives. `TaskbarCreated` is registered once with `RegisterWindowMessageW`, and the high-contrast taskbar palette reads `GetSysColor` and the live `SPI_GETHIGHCONTRAST` flag rather than WPF's cached `SystemParameters.HighContrast`. The only window Dejavu reorders is its own widget.
- `SHAppBarMessage(ABM_GETSTATE)` is a synchronous call into Explorer (shell32 delivers it to `Shell_TrayWnd` as `WM_COPYDATA`) and the taskbar tracker's only message to Explorer (separately, the pre-existing tray icon's `Shell_NotifyIcon` sends `WM_COPYDATA` to `Shell_TrayWnd` on the dispatcher under shell32's own `SendMessageTimeout` when its icon or text changes). Run it only on a single thread-pool worker with a 2 s observation timeout, never start a second worker while one is blocked, and use the cached result on the dispatcher. It is queried on enable and every settle, on `WM_SETTINGCHANGE` and every 15 s.
- Broadcasts arrive through a hidden, never-shown, unowned `HwndSource` (`WS_POPUP`, `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`): `TaskbarCreated` and `WM_DISPLAYCHANGE` rediscover and settle; `WM_SETTINGCHANGE` re-reads registry values and re-evaluates without hiding.
- Foreground changes arrive through `SetWinEventHook(EVENT_SYSTEM_FOREGROUND, …, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS)`. Out-of-context means no code is loaded into any other process and no message is sent to it; Windows queues the notification to Dejavu's own thread. The callback only coalesces one `Dispatcher.BeginInvoke`.
- `StateChanged` and `RaiseRequested` are raised on the dispatcher only from timer, hook or window callbacks, never synchronously inside `SetEnabled` or `NotifyShellChanged`, and `StateChanged` only when the state actually changed.
- Hook lifetime: the WinEvent delegate is rooted in a field for as long as the hook exists. `SetEnabled(false)` calls `UnhookWinEvent` on the dispatcher thread and tears down the hidden window and timers. `Dispose()` is idempotent and stops the tracker permanently.
- Controller order: construct the tracker after the `SystemEvents` subscriptions and before the first `ShowWidget`; enable it only while the widget is requested and the placement is `InTaskbar`; in `Dispose` call `_taskbarTracker.Dispose()` right after unsubscribing `SystemEvents` and before `_widget.Hide()`. Power resume and session unlock call `NotifyShellChanged` while enabled.
- Diagnostics record placement, tracker status and reason, band/anchor pixels, taskbar topmost and auto-hide flags, taskbar light mode, rediscovery count and widget raise counters. They never record titles or class names of other processes' windows.

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

- Dejavu never injects into, suspends, kills, or sends window messages to Claude Desktop, and never installs an in-context hook in it or any other process.
- The only system hook is the out-of-context foreground WinEvent hook that exists while the in-taskbar placement is enabled. Windows delivers foreground notifications for every process, including Claude Desktop, to Dejavu's own thread; Dejavu never acts on a Claude window: it never activates, moves, reorders or messages one, or reads its title. The only reads of the foreground window are the local process id, class name, style, zoom state, monitor and rectangle queries of fullscreen detection.
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
8. For in-taskbar changes, run the taskbar layout matrix (`Taskbar layout matrix: 1512 checked, 0 clipped, 0 over band, 0 mismatched`) and the tracker timelines (`Taskbar tracker transitions: 166 checked, 0 mismatched`), and repeat item 7 while docked. Also check taskbar clicks, Start, tray flyouts and jump lists near the overlay, fullscreen video and borderless games, auto-hide, logon, light/dark and high contrast, and 100/125/150/200 % scaling. The widget must never take focus, cover an open menu, or raise more than the rate limit allows (compare the raise counters in `status.json`), and turning the placement off must leave no hook, timer or hidden window behind.
