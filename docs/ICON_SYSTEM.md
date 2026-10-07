# Dejavu identity and icon system

Updated: 2026-10-02. Approved reference system; this documentation change does not replace native packaged assets.

Windows milestone 1 adds `DejavuBrandImage` and six original navigation geometries to `ThemeResources.xaml`, consumed by Settings. Packaged ICO/tray/shortcut assets and other window headers have not yet migrated. See [WINDOWS_REDESIGN.md](WINDOWS_REDESIGN.md).

## Separate identity, providers and actions

- **Dejavu:** Familiar Paradox / 모순의 프레임. Colored tile: `design/prototype/brand-mark.svg`; untiled vector and monochrome cut-out: `brand-exploration/frame-mark.svg` and `frame-mono.svg` within the reference. Themes do not recolor the tile. Existing native icons remain until an explicit asset migration.
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

Windows styling stays in `ThemeResources.xaml` / `ThemeManager.cs`. ICO/shortcut/tray conversion and packaging require explicit implementation and small-size/DPI testing. Mac catalogs, SF Symbols, Retina, status-item and packaging work are deferred to the Mac phase. Selected vectors or screenshots do not prove migration completion.

Keep the handwriting asset and OFL license together. Preserve licenses/attribution when importing assets. See [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and platform instructions.
