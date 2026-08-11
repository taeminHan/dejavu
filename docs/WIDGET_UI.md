# Widget UI architecture and verification

This document describes the widget contracts that must remain true while themes and layouts evolve.

## State flow

1. `DesktopApplicationController` refreshes Claude and Codex independently and creates an `ApplicationState`.
2. `TraySettings.ResolveServices` decides which providers are visible. Automatic detection uses provider snapshots or a ready provider status.
3. `UsageWidgetWindow.UpdateState` decides metric visibility and updates text/progress values.
4. `WidgetLayoutCalculator` calculates the window geometry and all service-dependent gaps.
5. `UsageWidgetWindow` applies those metrics and preserves either the custom top-left point or the configured right-edge anchor.

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
- progress visibility.

Its result owns window width and height, Claude/Codex gaps, provider vertical rhythm, and the Small-mode Codex margin. Do not add hard-coded window dimensions back to `UsageWidgetWindow`.

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
| Position | Top-right, taskbar-right, custom, monitor-edge clamp |

Important assertions:

- Reset credits, including zero, appear only in the expanded details window.
- The widget must contain no reset-credit badge, label, margin, or height branch.
- Codex headers use the same overlaid label/value structure as Claude metrics; do not reintroduce a badge placeholder column.
- Single-row width reclaims the former reset-credit allowance whenever Codex is visible.
- Codex-only Small mode has no leading 8 px provider gap.
- The always-visible widget has no product header, update-time row, or normal-state status-dot column.
- Both-service Small mode uses the 8 px provider gap only between visible providers.
- Auto-detection changing from no providers to one or two providers recalculates right-edge placement after the window resizes.
- Custom placement retains its saved top-left coordinate and clamps only when the resized widget would leave the working area.

## Theme rules

- Shared colors and styles belong in `ThemeResources.xaml`; theme values and style keys belong in `ThemeManager.cs`.
- A theme should change structure or rendering character, not only its palette.
- Paper Ink uses the bundled OFL-licensed handwriting font and pencil progress renderer. Widget card ledger underlines are intentionally absent; expanded details may retain record-sheet separators.
- Orbit Small mode uses circular progress with planet markers.
- Terminal uses terminal-like progress rendering and angular chrome.
- All themes must retain visible hover, pressed, disabled, loading, and focus states in settings and dialogs.
- Widget transparency applies only to chrome and decorative surface brushes. Keep the WPF window, text, icons, borders, and progress geometry at full opacity.
- The transparent widget uses layout rounding, pixel snapping, Display text metrics, fixed hinting, and grayscale antialiasing. At low background opacity, progressively move muted labels and metric text toward the theme's primary text color instead of fading the glyphs; progress geometry retains the accent color.

## Position behavior

Before a state or setting change, the window may have a different size. After applying the new metrics:

- custom placement: preserve the current top-left coordinate, then clamp to the active monitor working area;
- top-right: recompute `Left` from the new width and retain the top margin;
- taskbar-right: recompute both `Left` and `Top` from the new size and working area.

Service auto-detection is a size-changing event and follows the same rule as a density or row-layout change.

## Always-on-top behavior

- The WPF `Topmost` value and the native `WS_EX_TOPMOST` state must agree while the widget is visible.
- If Windows, Explorer, a display transition, session unlock or power resume removes the native topmost state, restore it with `SetWindowPos(HWND_TOPMOST)` using `SWP_NOACTIVATE`.
- Native window-position notifications are debounced and repair only a missing topmost state. Do not continuously move the widget to the front of the topmost band.
- Topmost recovery must not activate the widget, change its position or size, or compete with other intentional topmost windows.
- UAC secure desktop, the lock screen, exclusive full-screen content and another application's topmost window are outside the guarantee.

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
