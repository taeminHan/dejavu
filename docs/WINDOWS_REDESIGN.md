# Windows redesign implementation

Updated: 2026-10-07. Windows only. This record does not authorize a version bump, installer, tag or publication. The user requested a source commit and a separate website design refresh on 2026-10-07; push and release remain separate actions.

## Milestone 1: native Settings shell and identity

Implemented in WPF, not only the HTML reference:

- Six destinations: Display, Appearance, Connections, Behavior, Updates and Privacy. First open starts at Display; subsequent activation preserves the selected destination.
- Service, placement, density, row and graph controls belong to Display. Existing saved settings and controller events are unchanged.
- Connection cards and login/install actions move out of Privacy into Connections. Long descriptions and buttons stack instead of overlapping.
- Fixed navigation meaning and vector icons across all existing themes. Theme-dependent palette/row treatment remains; no persisted enum or presentation-name migration yet.
- Familiar Paradox vector appears in the Settings header without accent recoloring. Packaged application/tray icons and other windows still use their existing assets.
- A 920 x 700 DIP default and 800 x 600 minimum window, explicit two-column setting rows and wrapping descriptions. Vertical scrolling handles smaller content viewports; horizontal overflow is disabled.
- Inline update loading/results are stacked below their description. Existing automatic/manual update and install behavior is unchanged.
- Accessible names for pickers, caption controls and color swatches, and shared button/navigation/picker focus states.
- Existing WindowChrome and final non-interactive frame overlay are preserved. No widget geometry, provider/authentication, persistence, taskbar tracker or Mac implementation changes.

Ownership: `SettingsWindow.xaml(.cs)` owns this shell; `ThemeResources.xaml` owns identity vectors and reusable interaction styles. The previous theme-dependent navigation-label branches were removed instead of duplicating routing logic.

### Verification

- Isolated Release build: no warnings/errors.
- `DEJAVU_SETTINGS_ONLY=1`: 144 real WPF tree combinations (six themes, light/dark preference, default/minimum size, six pages), with no invalid layouts; 48 inline loading/result states. Synthetic connection text is used; the controller and providers are not started, and settings are not saved.
- Existing probe: 504 widget cases, 180 one-provider comparisons, 72 provider splits, 216 auto-detection comparisons; 24 Settings frame states; 1512 taskbar layouts; 166 tracker transitions; 48 Codex window variants; Orbit 120 states and Solar details 216 states, all without mismatches/failures.
- Preview PNGs are generated from WPF trees with sample data. They are not screenshots of a running installed app. This pass does not verify install/update, actual taskbar/foreground behavior, keyboard interaction or every physical display scale; those remain manual acceptance checks.
- Inspect at 100/125/150/200 percent DPI, minimum size, maximize/restore and all corners. Tab/arrow through navigation and pickers, open popup lists, verify connected/loading/offline/login-required states, and hide/reopen Settings without ending the widget process.

## Remaining milestones

Retro follow-up (2026-10-02): the native floating widget and usage details now use a real
bundled 5 x 7 bitmap alphabet, pixel-step frame, square-cell gauges and a stepped Small ring.
Korean text retains native fallback. The shared Retro font resource also reaches Settings,
but this is not completion of the full settings/dialogs structural theme migration or the
Arcade presentation-name migration. Taskbar rendering, Orbit and Paper Ink are preserved.
The focused Retro probe checks 144 native widget/detail states and font resource resolution.
Existing full matrices and 144 Settings/48 inline update states pass. PNG evidence is generated
from synthetic WPF trees; installed lifecycle and physical fractional-DPI acceptance remain manual.

Orbit follow-up (2026-10-02): charts use selected planets in actual solar order, Venus → Earth → Mars → Jupiter → Saturn, while provider legends and metric identities stay unchanged. Floating provider systems use the same ordering rule; geometry, taskbar rendering, credits and optional-window semantics remain unchanged. See `WIDGET_UI.md`.

1. **Theme migration:** implement Studio/Arcade/Prism/Console shape and progress treatment across widgets, details, Settings and dialogs. Preserve stored enum values, taskbar-neutral geometry, Orbit and Paper Ink/Field Notes. Do not announce new presentation names before the rendering migration.
2. **Details and motion:** migrate expanded usage hierarchy/shared action icons; implement short fill reveal on open with reduced-motion support, cancellation and no continuous animation. Preserve details-only credits and existing Orbit solar semantics.
3. **Product acceptance:** synchronize remaining headers/packaged icon assets, run native DPI/pointer/accessibility and provider-state checks, then separately validate installed update/uninstall. Commit/release only when requested.

Mac implementation stays deferred to a Mac. Do not use this plan as authorization to scaffold or publish Mac changes, rewrite credentials, replace the installed app, or commit/push work without an explicit user request.
