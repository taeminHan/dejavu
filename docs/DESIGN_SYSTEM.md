# Dejavu design system

Updated: 2026-10-02. Approved redesign and implementation handoff; not a claim that the shipped app already matches the reference.

## Scope and status

**Develop Windows now. Implement and validate macOS later, separately on a Mac.** Existing native Windows and Mac source must be preserved. Mac work is deferred, not missing source or a prerequisite for Windows completion.

The editable HTML/CSS/JS reference lives in [`design/prototype/`](../design/prototype/AGENTS.md), with fixed sample data, selected vectors and licensed assets. It is not the deployment website, a provider integration, a SwiftUI app or a WPF acceptance test. Copied reference evidence is historical HTML evidence only.

| Area | Approved direction | Native boundary |
| --- | --- | --- |
| Windows | New brand, four redesigned themes, consistent settings/details/widgets | WPF migration and actual visual/DPI verification are separate implementation tasks. Preserve settings and current behavior. |
| Orbit | Existing provider systems in widgets and one solar system in details | Current ownership is in [WIDGET_UI.md](WIDGET_UI.md); the HTML gallery intentionally does not replace it. |
| Paper Ink / Field Notes | Existing handwriting and wavy pencil character | HTML is a direction-preserving approximation, not a pixel-identical native drawing. |
| macOS | Theme-free, menu-bar-first macOS 27 direction | HTML refinement exists. Reconcile existing SwiftUI/AppKit implementation only when work resumes on a Mac. |

Windows migration has started: the native Settings shell now has six pages and the selected brand/navigation vectors. Retro Night widgets/details now use a bundled bitmap alphabet, square-cell gauges and stepped pixel rings/frames. The other redesigned theme renderers, full Settings/dialogs theme migration and details-opening motion remain unfinished. Track actual completion and remaining work in [WINDOWS_REDESIGN.md](WINDOWS_REDESIGN.md); the table above must not be read as shipped-feature status.

## Brand

Selected identity: **Familiar Paradox / 모순의 프레임**. A familiar frame has an unexpected folded relationship. Do not claim a mathematically impossible object or certified optical illusion.

- Reference colored tile: `design/prototype/brand-mark.svg`.
- Untiled vector: `design/prototype/brand-exploration/frame-mark.svg`.
- Monochrome tray/status silhouette: `design/prototype/brand-exploration/frame-mono.svg`.
- Forest/sage is the identity treatment, not a compulsory UI accent. Themes do not recolor the full-color tile.
- Selected vectors do not automatically replace `assets/dejavu.ico`, installed shortcuts or Mac asset catalogs. Native conversion/packaging/small-size verification require explicit implementation.
- Provider identities and action icons stay separate; see [ICON_SYSTEM.md](ICON_SYSTEM.md).

## Windows themes

Presentation names/prototype keys are proposals, **not persisted enum migrations**. `TraySettings.cs` uses `WidgetVisualTheme`; preserve stored values and migration compatibility.

| Native family | Presentation / reference key | Structure | Progress |
| --- | --- | --- | --- |
| Modern | Studio / `modern` | Ordered instrument panels, restrained selection, numeric columns | Quarter-tick scale; compact rings in Small |
| RetroNight | Arcade / `retro` | Pixel-step outline, metric cells, square controls, fixed-width numbers | Pixel segments clipped to the exact percentage |
| FluentGlass | Prism / `glass` | Rounded inset panels, capsule cells, restrained depth | Rounded luminous track; compact rings in Small |
| TerminalMono | Console / `terminal` | Angular chrome, fixed-width text, command hierarchy | Character blocks in brackets, percentage-clipped rather than rounded blobs |
| PaperInk | Field Notes / `paper`, preserved | Existing handwriting, plain paper surfaces and simple borders | Wavy colored-pencil character; no ledger line beneath widget bars |
| Orbit | Orbit, preserved | Provider systems in widgets; one solar system in details | Current planet/arc semantics; no replacement reference renderer |

Themes change structure/rendering character, not only color. Apply approved language consistently to settings, details, update decisions, controls and floating widgets. Taskbar chrome and docked geometry remain OS-owned/native-neutral. Gallery specimens are compressed form studies; LIVE PREVIEW uses logical-size reference geometry, not native screenshots.

### Native ownership

- `ThemeResources.xaml`: semantic resources, shared buttons/controls/scrollbars/progress and interaction states.
- `ThemeManager.cs`: values and capabilities; do not duplicate palettes in windows.
- `WidgetLayoutCalculator.cs`: all widget geometry, including taskbar, theme, density and service inputs.
- `UsageWidgetWindow.xaml(.cs)`: binding, visibility, pointer behavior and DPI-correct placement.
- `UsageDetailsWindow.xaml(.cs)`: expanded usage; `OrbitDetailsView` owns combined solar-system details.
- `SettingsWindow`, `OnboardingWindow`, `UpdateWindow`: their separate information and interaction surfaces.

Do not copy HTML pixel values into WPF as another layout calculator. Read complete affected native files and preserve [WIDGET_UI.md](WIDGET_UI.md) and [STABILITY.md](STABILITY.md). Do not introduce a new UI framework merely to copy visual patterns without authorizing that architectural change.

## Information and interaction invariants

- Small / Compact / Comfortable correspond to 작음 / 중간 / 큼 and are distinct layouts. Density, graphs and row preference stay independent.
- Two rows work only with two visible providers, Codex above Claude. Zero/one-provider geometry matches one row; equivalent Auto/Both data gives equivalent geometry.
- Hidden services and optional Codex windows leave no empty slot, margin or separator. Credits and expiry are details-only: no widget badge, product header or reserved cell.
- A normalized finite percentage drives text, graphs and accessibility. Unknown/expired stays `--%`, not fake zero or stale text over an empty graph.
- Graph off removes only its footprint. Values, reset times, padding and borders stay readable and unclipped.
- Opacity affects backgrounds, never text/icons/fills. Preserve layout rounding/pixel snapping and readability at low opacity and supported DPI scales.
- Preserve custom top-left positions and configured default edge anchors across size/theme/service changes. Click opens details; dragging moves without opening details. Docked placement is not draggable.
- Settings update checks show inline loading/results; a discovered update may need a styled decision. Buttons, release notes, download progress and scrollbars share usable theme states.
- Settings retain WindowChrome ownership and continuous non-hit-testable borders, including corners and maximize/restore. Do not introduce a second clip or transparent resizable window.
- Errors are not automatically login failures. Preserve valid values only within freshness rules, with a clear recovery action. Visual controls do not own providers, credentials or refresh polling.
- Korean copy is short and natural. Off toggles, dropdown entries, disabled/loading controls and keyboard focus are distinguishable; icon-only actions have accessible names.
- Settings headings are plain destination names (표시, 꾸미기, 연결, 동작, 업데이트, 개인정보). Do not add slogans, numbered kickers or duplicate introductory copy. Keep descriptions only for behavior, availability, limits, recovery and privacy; use concise status text for update checks.

## Detail-opening motion

The reference uses a 180 ms subtle entrance and 420 ms fill reveal with at most 120 ms staggering, once per closed-to-open presentation. These are Dejavu choices, not Apple-mandated timings or already implemented WPF guarantees.

- Numbers/accessibility show final percentages immediately. Animate visible fill, not numbers, track size or layout.
- Reveal pencil strokes/terminal glyphs without scaling them. Zero/unknown data gets no fabricated fill.
- Close, replacement and reduced-motion changes cancel effects. Unchanged resize/render must not replace focused nodes or restart the reveal.
- System reduced motion wins; animation-off shows final content immediately. No perpetual widget/planet animation.
- Native integration needs independent rendering and system-preference tests. VM checks do not establish native behavior.

## Deferred macOS direction

Approved target: macOS 27, **no product themes**, menu-bar first. Preserve the reference and existing `macos/` code; do not scaffold another Mac application or implement this phase during Windows work.

The 2026-10-02 HTML refinement used [Apple's macOS overview](https://www.apple.com/os/macos/), [macOS 27 design resources](https://developer.apple.com/design/resources/), [WWDC26 design](https://developer.apple.com/wwdc26/guides/design/) and [HIG toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars):

- Edge-to-edge settings sidebar, content-aligned toolbar and grouped settings rows.
- Monochrome provider status marks with selected percentages; attached details close on repeated click, outside click or Esc.
- Top-mounted settings/refresh remain usable while the body scrolls. Consistent label/graph/value columns and named credits in details.
- System/light/dark appearance, opaque readable content and restrained materials on navigation/control surfaces.
- Reduced Motion/Transparency and contrast support. No desktop-widget counterpart, density/row/topmost controls, custom opacity slider or utility Dock entry in the approved new direction.

Use appropriate standard SwiftUI/AppKit facilities, semantic colors, typography, actual SF Symbols and system materials on the Mac. CSS blur and Windows browser fonts are not authentic Liquid Glass or Mac typography validation. Reference sizes/radii/timings are not Apple-mandated metrics.

Old Mac plans describe floating/WidgetKit and different status-menu surfaces. They record existing work, not permission to continue them or silently delete them. Reconcile migration scope against actual native code on a Mac; see [macos/AGENTS.md](../macos/AGENTS.md).

## Validation and migration

1. Reference changes: use its syntax/renderer/motion checks and relevant browser states. `design/prototype/*-validation.json` contains dated copied HTML evidence, not fresh native results.
2. Windows integration: follow [DEVELOPMENT.md](DEVELOPMENT.md) and [WIDGET_UI.md](WIDGET_UI.md), including actual WPF/taskbar/tracker, provider states, DPI and pointer matrices. HTML dimensions/VM checks do not replace them.
3. Mac verification: later on a Mac, with actual SDK/OS, VoiceOver, Retina/multiple displays and native materials. Confirm current guidance and minimum OS requirements then.
4. Native assets, signing, install/update/uninstall, CI changes and publication are separate authorized tasks. Documentation does not authorize commits, pushes or releases.
