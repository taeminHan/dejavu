# Dejavu identity and icon system

Updated: 2026-10-17. Windows 0.9.7 identity implementation; executed acceptance evidence belongs in RELEASE_CHECKLIST.md and the release evidence assets.

Windows now uses the approved mark for application/window icons, runtime tray mark mode, installer/execution stubs and shortcut icon sources. Settings, onboarding, details and update headers share `DejavuBrandImage`. Do not confuse this migration with the separate full-theme/motion milestones in [WINDOWS_REDESIGN.md](WINDOWS_REDESIGN.md).

## Separate identity, providers and actions

- **Dejavu:** Familiar Paradox / 모순의 프레임. Production colored tile `assets/brand-mark.svg` and monochrome `assets/brand-mark-mono.svg` must match the approved prototype vectors. `assets/brand-icons.json` records SVG/ICO/frame provenance. Theme-independent WPF vectors preserve the 64 x 64 viewBox; `BrandIcon` owns frozen application images and caller-owned GDI icons. Themes do not recolor the tile.
- **Providers:** preserve Claude Spark and OpenAI Blossom rather than drawing substitutes. The reference reuses `claude-menu.png` and `codex-menu.png`. Keep provider names or accessible labels when their meaning is not obvious.
- **Actions:** original SVGs in one `design/prototype/icons.js` registry, not Lucide or SF Symbols. Future Windows library adoption replaces the action system coherently. Native Mac actions use actual SF Symbols/system controls when that phase resumes.
- **OS context:** sample Finder/taskbar/traffic-light/quick-settings drawings are reference context, not product icon specification or permission to modify Explorer.
- **Theme artwork:** Orbit planets are visualizations, not generic action icons. A refresh arrow never represents credit balance.

## Geometry and accessibility

- Reference action SVGs: 24 x 24 viewBox, 2-unit stroke, rounded ends/joins.
- Reference navigation/buttons: 18 px; compact panel actions: 14 px; close: 16 px. These are prototype choices, not hardcoded native requirements.
- Semantic foreground/currentColor, not per-window literal colors. Normal/selected/hover/pressed/disabled/loading/focus states stay legible.
- Decorative glyphs are hidden from accessibility; controls have visible text or accessible names. Icon size is not hit-target size.
- State is not color-only. Monochrome tray/status marks need light/dark/high-contrast OS visibility.
- Provider silhouettes, product identity and action meanings remain consistent across Windows themes. Credits remain named counts in details, not arrow/count badges in widgets.

## Meaning map

| Key | Meaning |
| --- | --- |
| display | Placement and visible services |
| appearance | Appearance / Windows themes |
| connections | Provider connections |
| behavior | Startup and behavior |
| updates | Check for a new app version |
| privacy | Privacy and local data |
| settings | Open settings |
| refresh | Refresh usage, not update the app or spend credits |
| details | Expanded usage/reset information |
| expand | Expand preview, not an external link |
| close | Close the current panel |
| sun / moon | Light/dark appearance, not a product theme |

## Native boundary

Windows styling stays in `ThemeResources.xaml` / `ThemeManager.cs`. `tools/GenerateIcon.ps1` (Windows) and `tools/GenerateWindowsIcons.swift` (asset tooling on Mac, not a Mac app change) generate 16/20/24/32/40/48/64/128/256 ICO frames from those vectors. The application/installer uses the colored tile; tray mark mode selects dark or light monochrome ink from the actual taskbar appearance and native contrast background. Persisted `TrayIconStyle.ClaudeMark`, Percentage and Hidden retain their numeric meanings. Startup, appearance and DPI changes must not flash a generic/old icon or leak handles.

`WindowsReleaseProbe` checks all packaged icon frames against the approved provenance, not merely the source build. `TestWindowsRelease.ps1` performs isolated installation and resolves the actual Start Menu shortcut and Apps & Features icon. `--validate-brand=<absolute empty directory>` is a controller-free acceptance route before Velopack/settings/providers, producing runtime images and synthetic WPF evidence; it must never become an authentication or user-settings migration path. Interactive Explorer, physical DPI and installed automatic-update acceptance remain distinct from CI evidence. Mac functionality is unchanged in 0.9.7.

Keep the handwriting asset and OFL license together. Preserve licenses/attribution when importing assets. See [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and platform instructions.
