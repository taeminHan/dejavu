# Widget UI architecture and verification

This document describes the widget contracts that must remain true while themes and layouts evolve.

## State flow

1. `DesktopApplicationController` refreshes Claude and Codex independently and creates an `ApplicationState`.
2. `TraySettings.ResolveServices` decides which providers are visible. Automatic detection uses provider snapshots or a ready provider status.
3. `UsageWidgetWindow.UpdateState` decides metric visibility and updates text/progress values.
4. `WidgetLayoutCalculator` calculates the window geometry and all service-dependent gaps.
5. `UsageWidgetWindow` applies those metrics and preserves the custom top-left point, the configured right-edge anchor or, while docked, the taskbar anchor supplied by `TaskbarTracker`.

Keep those responsibilities separate. Data availability must not be inferred from a WPF element's current visibility, and geometry must not depend on text measurement spread across event handlers.

## Data semantics

| Value | Display rule |
|---|---|
| Claude snapshot missing | Claude metrics use `--%` only when the selected service policy still forces Claude visible. |
| Codex snapshot missing | Codex usage uses `--%` only when the selected service policy still forces Codex visible. |
| Reset credits | Show the value and expiry only in `UsageDetailsWindow`; the always-visible widget reserves no space for it. |
| Percentage outside 0–100 | Clamp once, then use the same value for text and progress geometry. |
| Refresh with previous snapshot | Previous values may remain visible while status indicates loading. Do not discard the provider slot. |

## Layout ownership

`WidgetLayoutCalculator.Calculate` is a pure geometry decision. Its request contains every input that can change size:

- density;
- one-row or two-row layout;
- visual theme;
- Claude/Codex visibility;
- progress visibility;
- in-taskbar docking (`InTaskbar`) and the taskbar band height in DIPs.

Its result owns window width and height, Claude/Codex gaps, provider vertical rhythm, and the Small-mode Codex margin. While docked, `WidgetLayoutMetrics.Taskbar` (`TaskbarLayoutMetrics`) also owns cell width, gaps, padding, line heights, progress geometry and the anchor gap. Do not add hard-coded window dimensions back to `UsageWidgetWindow`.

`TwoRows` is a provider split, not a different one-provider presentation. It becomes effective only while Claude and Codex are both visible. With Claude only, Codex only, or no detected provider, selecting `TwoRows` must produce the same window geometry, active panel, spacing and Small-mode orientation as `SingleRow`. If automatic detection later exposes the second provider, the saved `TwoRows` preference becomes effective at that point.

Linear height is composed from the theme's outer chrome, the card/text row that remains visible, and the exact progress visual plus its density-specific top margin. Turning progress off removes only that final progress footprint; it must never remove theme padding or borders. Keep a small layout-rounding guard above the measured natural height.

The XAML still owns intrinsic control geometry such as the 30 px Small-mode rings and 48 px metric cells. If those change, update the calculator and this document together.

Compact and Comfortable linear layouts use 75% of their former base content width. Theme-specific chrome allowances remain unscaled so Retro, Glass, Terminal, Orbit, and Paper treatments do not clip their labels or decoration.

## Required state matrix

At minimum, trace or exercise these axes after a widget change:

| Axis | Cases |
|---|---|
| Services | Claude only, Codex only, both, neither |
| Density | Small, Compact, Comfortable |
| Layout | One row, two rows |
| Progress | On, off |
| Data state | Loading, ready, partial, login required, rate limited, offline |
| Position | Top-right, taskbar-right, custom, monitor-edge clamp, in-taskbar (docked, suppressed, fallback) |
| Taskbar band | 32, 40 and 48 DIP; light and dark taskbar; high contrast |
| Display scale | 100 %, 125 %, 150 %, 200 % |

Important assertions:

- Reset credits, including zero, appear only in the expanded details window.
- The widget must contain no reset-credit badge, label, margin, or height branch.
- Codex headers use the same overlaid label/value structure as Claude metrics; do not reintroduce a badge placeholder column.
- Single-row width reclaims the former reset-credit allowance whenever Codex is visible.
- Codex-only Small mode has no leading 8 px provider gap.
- The always-visible widget has no product header, update-time row, or normal-state status-dot column. The docked no-provider message cell is the only exception; see [Taskbar geometry and look](#taskbar-geometry-and-look).
- Both-service Small mode uses the 8 px provider gap only between visible providers.
- Both-service Small `TwoRows` mode orders Codex above Claude, matching the linear two-row layout and Settings copy.
- With zero or one visible provider, `SingleRow` and `TwoRows` have identical geometry and active visual structure.
- Auto-detection changing from no providers to one or two providers recalculates right-edge placement after the window resizes.
- Custom placement retains its saved top-left coordinate and clamps only when the resized widget would leave the working area.
- While docked in the taskbar, every density, row layout and visual theme produces identical geometry for the same services, progress setting and band.
- While docked, only `TaskbarPanel` is visible; hidden providers leave no cell, gap or margin, and the visible cells span exactly the padded card.
- A docked widget is never taller than the taskbar band, and its right edge never passes the anchor.

## Theme rules

- Shared colors and styles belong in `ThemeResources.xaml`; theme values and style keys belong in `ThemeManager.cs`.
- A theme should change structure or rendering character, not only its palette.
- Paper Ink uses the bundled OFL-licensed handwriting font and pencil progress renderer. Widget card ledger underlines are intentionally absent; expanded details may retain record-sheet separators.
- Orbit uses vector celestial markers on circular progress: Claude 5-hour limits use a cratered moon, Claude weekly limits use Earth, Fable uses a ray-drawn sun, and Codex always uses Saturn. Small mode uses the same mapping with a larger marker while retaining its 30 px ring geometry.
- Terminal uses terminal-like progress rendering and angular chrome.
- All themes must retain visible hover, pressed, disabled, loading, and focus states in settings and dialogs.
- Widget transparency applies only to chrome and decorative surface brushes. Keep the WPF window, text, icons, borders, and progress geometry at full opacity.
- The transparent widget uses layout rounding, pixel snapping, Display text metrics, fixed hinting, and grayscale antialiasing. At low background opacity, progressively move muted labels and metric text toward the theme's primary text color instead of fading the glyphs; progress geometry retains the accent color.

## In-taskbar placement

`WidgetPlacement.InTaskbar` ("작업표시줄 안 · 시계 옆") is opt-in; the default remains `TaskbarRight`. It is persisted as the integer `3`; enum values are append-only.

### Overlay design

The existing topmost WPF widget window is placed over the primary Windows 11 taskbar band so that its right edge ends just left of the notification area (`TrayNotifyWnd`). It is not part of the taskbar: it stays a Dejavu window with no Explorer owner or parent and keeps its own input queue. It never uses `SetParent`, `GWLP_HWNDPARENT` or `WindowInteropHelper.Owner = Shell_TrayWnd`, `AttachThreadInput`, DLL injection, `SetWindowBand`, uiAccess, `SendMessage`/`PostMessage` to Explorer windows, or `GetWindowText` of other processes. `TaskbarTracker` owns taskbar discovery; the widget receives a device-pixel `TaskbarDock` through `SetTaskbarDock`, and its only other taskbar interaction is the local z-order check described under [Scoped exception while docked in the taskbar](#scoped-exception-while-docked-in-the-taskbar).

### Tracker states

| Status | Widget behavior | Reasons |
|---|---|---|
| `Docked` | Taskbar look at the dock anchor. | — |
| `Suppressed` | Real `Hide()`; shown again when the state changes. The dock is kept. | `settling` (startup, Explorer restart or a replaced/lost `Shell_TrayWnd`, display change, resume/unlock, the first evaluation after the PC slept, and leaving a fallback for a dockable taskbar, even one a fullscreen window covers; until two 250 ms samples report the same geometry and the auto-hide query finished or 2 s passed; geometry that never repeats docks anyway 10 s after settling began), `fullscreen` (the taskbar lost `WS_EX_TOPMOST`, or another process's non-shell, non-maximized foreground window covers the taskbar's monitor; shell windows are `Progman`, `WorkerW`, `Shell_TrayWnd`, `Shell_SecondaryTrayWnd` and, only when owned by the taskbar's Explorer process, `XamlExplorerHostIslandWindow` for Task View, Alt+Tab and Snap Assist) |
| `Fallback` | Ordinary floating `TaskbarRight` widget with the normal density, layout and theme. The saved placement stays `InTaskbar`. | `non_xaml_taskbar` (Windows 10 taskbar, ExplorerPatcher, StartAllBack), `vertical`, `autohide`, `rtl_or_mirrored`, `band_too_small`, `shell_mismatch` (while settling, these end settling only after the same reason has repeated on the 250 ms samples for 2 s), and `taskbar_missing`/`tray_missing`. While settling those two stay `settling` until 10 s after settling began; outside settling they fall back at the next evaluation, except a lost or replaced `Shell_TrayWnd` handle, which starts settling again. |
| `Inactive` | Normal placement rules. | Placement is not `InTaskbar`, or the widget is not requested. |

The evaluation that starts settling always reports `settling`. After that, a hard fallback ends settling once it has persisted for 2 s, missing taskbar/tray and unstable geometry stay `settling` for up to 10 s, and otherwise fullscreen comes before `Docked`. Outside settling, hard fallbacks win over fullscreen and `Docked`, and a `Fallback` that becomes dockable settles again before it docks or reports `fullscreen`. On a Windows 10 taskbar the widget is therefore hidden for about 2 s after each settle before the floating widget appears. The Settings placement row shows a Korean one-line status for docked, fallback-with-reason, fullscreen and settling.

### Taskbar geometry and look

- The calculator's taskbar branch ignores density, row layout and visual theme and always uses a single row: 38 DIP cells, 4 DIP between Claude cells, 8 DIP before Codex only while Claude is visible, 6/2 DIP card padding, 12 DIP label and 14 DIP value lines, a 1 DIP guard. Widths are 180 (both), 134 (Claude), 50 (Codex) and 50 (neither, one message cell).
- Height is 31 DIP without and 36 DIP with progress. Progress is shown only when enabled, a provider is visible and the band is at least 38 DIP. `MinimumTaskbarBandHeight` is 32 DIP; a smaller band is `band_too_small`.
- Placement is pixel-snapped from the dock: right edge at `AnchorRight - round(AnchorGap × scale)` with a 4 DIP `AnchorGap`, clamped at the band's left edge, vertically centred in the band. The anchor is the tray's left edge; with a left-aligned taskbar and a visible Widgets button it moves `round(160 × system scale)` pixels further left.
- The card uses `WidgetCardTaskbar`: a 1/255-alpha surface so the whole rectangle is hit-testable, no border or shadow, 4 DIP radius, texture overlay collapsed. Text follows the taskbar theme (`SystemUsesLightTheme`, not `AppsUseLightTheme`), bars use the user accent, high contrast uses the current Win32 system colors (`GetSysColor` window, window text, gray text and highlight, re-applied on `WM_SYSCOLORCHANGE` and `WM_THEMECHANGED` while docked, with the live `SPI_GETHIGHCONTRAST` flag rather than WPF's cached `SystemParameters.HighContrast`), and threshold colors use `TaskbarWarningBrush`/`TaskbarDangerBrush`.
- Text and bars use the same clamped value; missing data is `--%` with an empty bar. The tooltip and automation name carry a short Korean summary. Reset credits never appear.
- With no visible provider, the single `TaskbarMessageCell` shows the fixed muted label `dejavu` over `--%` with no bar; `state.Message` is carried only by the tooltip and automation name. This is the only product-name text on the always-visible widget and is limited to the docked neither-available state.
- Left click toggles details and right click opens Settings. Dragging is disabled: press-move-release counts as a click and the placement never converts to `Custom`.
- Density, row-layout and background-opacity settings stay enabled; their Settings descriptions state that they apply only outside the taskbar.

### Known limitations

- The overlay is covered while Start, Search, Quick Settings or Notification Center is open.
- After a taskbar click it can drop behind the taskbar briefly until the next raise.
- v1 does not measure free taskbar space, so on a crowded centred taskbar it may overlap task buttons.
- Only the primary taskbar is used; secondary-monitor taskbars are ignored.

## Position behavior

Before a state or setting change, the window may have a different size. After applying the new metrics:

- custom placement: preserve the current top-left coordinate, then clamp to the active monitor working area;
- top-right: recompute `Left` from the new width and retain the top margin;
- taskbar-right: recompute both `Left` and `Top` from the new size and working area;
- in-taskbar: recompute from the dock; without a dock (fallback) use the taskbar-right rule. `KeepCurrentPositionVisible` never runs and nothing is written to the saved custom coordinates.

Service auto-detection is a size-changing event and follows the same rule as a density or row-layout change.

WinForms `Screen` rectangles and Win32 rectangles are device pixels because WPF makes the process system-DPI-aware. Every placement converts them with the window's `CompositionTarget.TransformFromDevice` (fallback `VisualTreeHelper.GetDpi`) before assigning `Left`/`Top`, and the drag path converts its pixel delta to DIPs. `UsageDetailsWindow.ShowNear` follows the same rule. The conversion is the identity at 100 %.

## Custom window frames

- `SettingsWindow` keeps `WindowChrome` as the only owner of the native outer shape. Do not add a second full-window `Clip` to its frame.
- Draw `WindowFrame` as the last, transparent, non-hit-testable overlay above `SettingsShell` so content cannot cover the rounded outline and the outline cannot intercept controls. Inset a rounded frame by one physical pixel and derive its radius concentrically from the native radius at the current DPI; its antialiased edge must not sit on the native crop boundary.
- Enable layout rounding and pixel snapping across the Settings shell. Normal windows use the theme radius and frame thickness; maximized windows use a zero-radius, zero-thickness WPF overlay while Windows supplies the rectangular maximized region.
- Do not enable `AllowsTransparency` on the resizable Settings window; it would trade away native resize, shadow and compositor behavior.

## Always-on-top behavior

- The WPF `Topmost` value and the native `WS_EX_TOPMOST` state must agree while the widget is visible.
- If Windows, Explorer, a display transition, session unlock or power resume removes the native topmost state, restore it with `SetWindowPos(HWND_TOPMOST)` using `SWP_NOACTIVATE`.
- Native window-position notifications are debounced and repair only a missing topmost state. Do not continuously move the widget to the front of the topmost band.
- Topmost recovery must not activate the widget, change its position or size, or compete with other intentional topmost windows.
- UAC secure desktop, the lock screen, exclusive full-screen content and another application's topmost window are outside the guarantee.

### Scoped exception while docked in the taskbar

The taskbar is itself topmost and moves to the front of the topmost band when clicked. Only while `IsTaskbarDocked` is true, `RaiseAboveTaskbarIfCovered` may reorder the widget:

- It acts only when a local `GetWindow(GW_HWNDPREV)` walk from the widget finds `Shell_TrayWnd` above it. The walk ends at the top of the z-order; its 65536-step bound (the per-session USER handle ceiling) only guards against concurrent reordering, so hidden topmost windows between the widget and the taskbar never hide a covering taskbar.
- It inserts the widget directly above the taskbar (`insertAfter = GetWindow(taskbar, GW_HWNDPREV)`, or `HWND_TOPMOST` when none) with `SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER`.
- Triggers are the tracker's `RaiseRequested` reasons (`foreground`, then `foreground_followup` at +300 ms and +600 ms, and the 1 s `backstop`, which is skipped while settling), which the tracker sends only while `Docked`, plus the controller's own `docked` check. `DesktopApplicationController.UpdateWidgetVisibility` makes that check after every `ApplyTaskbarState`: widget show, settings apply, tracker state change, and session unlock or power resume.
- Raises are at least 250 ms apart and at most 60 per rolling minute; the +300 ms follow-up clears that interval after a raise at the foreground change. If the widget is still covered after a raise (Start or a system flyout band), the widget records the foreground window and blocks the backstop. Any other request (`foreground`, `foreground_followup`, `docked`) lifts the block, and so does the backstop once another window is in the foreground, which also covers Dejavu's own windows and changes made while the widget was hidden.
- It never activates the widget, never moves or resizes it, and never jumps above windows that are already above the taskbar.

## Manual visual checklist

1. Start with automatic detection and confirm no empty provider slot appears while loading.
2. Force Claude-only and Codex-only display in each density and row layout.
3. Confirm the widget never shows or reserves space for reset credits; confirm the expanded details window still shows their value and expiry.
4. Toggle progress visibility and look for clipping or unexplained empty space.
5. Switch every theme with Claude only, Codex only, and both visible.
6. Move the widget to a custom position, change density/layout/services, and confirm its top-left anchor stays stable.
7. Return to a right-edge placement and repeat; the right margin must remain stable.
8. Left-click without dragging to open details; drag beyond the system threshold to move without opening details.
9. Check the expanded usage window separately because its separators and density are intentionally independent from the widget.
10. After Win+L/unlock, sleep/resume, Explorer restart and display changes, confirm the widget remains above normal windows without taking keyboard focus.
11. Check all four Settings corners in light and dark mode at normal size, then maximize and restore. The outline must remain continuous with no square background leak.
12. Select 작업표시줄 안 · 시계 옆 and confirm the widget sits left of the clock, fits the band, and switches to the floating widget and back when the placement changes.
13. Click the taskbar, open Start, tray flyouts and jump lists near the overlay; the widget must return above the taskbar without taking focus and must never cover an open menu.
14. Play fullscreen video and a borderless game on the primary monitor; the widget must hide and return afterwards. Win+Tab (Task View), Alt+Tab and Snap Assist while docked must not hide it.
15. Enable taskbar auto-hide, restart Explorer, change the resolution and sign out/in; confirm fallback, settling and re-docking without a floating-widget flash while Explorer rebuilds the taskbar.
16. Switch Windows light/dark mode and high contrast, and switch between two contrast themes while docked; taskbar text must follow the taskbar theme and the current contrast colors.
17. Repeat at 100 %, 125 %, 150 % and 200 % scaling for every placement, including the fallback floating widget and the details window.
18. Check a left-aligned taskbar with Widgets, a crowded centred taskbar, an RTL display language and ExplorerPatcher/StartAllBack (expect fallback).

The structural layout probe must also measure and arrange the real WPF tree for all themes, densities, layouts, forced and automatically detected provider states, and progress on/off. Every provider-present case must fit inside the calculated window height, every zero/one-provider `TwoRows` case must match its `SingleRow` visible-element geometry, and automatic detection must match the equivalent forced-provider result; a successful compile alone does not satisfy this check.

The probe also docks a synthetic `TaskbarDock` for the same axes at 32, 40 and 48 DIP bands (1512 cases) and must print `Taskbar layout matrix: 1512 checked, 0 clipped, 0 over band, 0 mismatched`. It fails when card content or any label/value (including a `100%` sample) does not fit, when the window is taller than the band or passes the anchor, when a non-taskbar panel is visible, when a hidden provider leaves a gap, when bar visibility disagrees with progress, provider visibility and the 38 DIP threshold, or when geometry differs across themes, densities, layouts or forced/auto-detected services. It then replays the tracker's settle timelines (see `docs/DEVELOPMENT.md`) and must print `Taskbar tracker transitions: 166 checked, 0 mismatched`.
