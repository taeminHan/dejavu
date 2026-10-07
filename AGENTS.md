# Dejavu contributor instructions

Updated: 2026-10-02. Current implementation phase: **Windows only**.

These instructions apply to the entire repository. Dejavu is a public Windows 11 WPF product, not a developer-only tray utility. Preserve existing user settings, local-only data handling, and the always-visible widget behavior.

## Current phase and design handoff

- Continue Windows redesign, refactoring and quality work now. The user will resume macOS implementation separately on a Mac; it is not a parallel task or a prerequisite for completing a Windows milestone.
- `docs/DESIGN_SYSTEM.md` and `docs/ICON_SYSTEM.md` record the approved redesign, identity and platform boundaries. `design/prototype/` is an editable HTML reference with simulated data, not the shipped WPF app or deployment website. Read its own `AGENTS.md` before editing it.
- Selected brand: **Familiar Paradox / 모순의 프레임**. Studio, Arcade, Prism and Console are proposed names for redesigned Windows families; Field Notes preserves Paper Ink. Do not rename persisted enums or claim these designs are implemented in WPF merely because the reference exists.
- Preserve native Orbit planetary widgets and combined solar-system details, and Paper Ink handwriting/wavy pencils. Mac has no product themes; its future redesign is menu-bar first.
- Existing `macos/` source and workflows are prior implementation foundations. Preserve them. Do not develop, remove, scaffold, build or publish Mac functionality in a Windows-only task without explicit authorization. Read `macos/AGENTS.md` when that phase resumes.
- Shared contracts may change for an authorized Windows task; identify Mac compatibility impact without silently redesigning Mac code or making deferred native Mac validation block Windows work. Existing release automation includes Mac paths: inspect it before a release, not as authorization to alter workflows now.
- Latest user decisions and repository contracts override stale personal skills: reset credits are details-only, the widget has no header, and zero/one-provider two-row preferences must not alter geometry. Never revive obsolete badge/header slots.
- Do not spawn parallel agents unless the user explicitly authorizes delegation. Handoff documents do not authorize separate implementation tasks.

## Start here

For redesign work, first read `docs/DESIGN_SYSTEM.md` and `docs/ICON_SYSTEM.md` for approved decisions and prototype/native boundaries. Current behavior and safety remain governed by the documents below until deliberately migrated.

1. Read `docs/ARCHITECTURE.md` for runtime ownership, provider detection, storage, update and uninstall boundaries.
2. Read `docs/DEVELOPMENT.md` for build, preview, integration-test and release workflows.
3. Read `docs/WIDGET_UI.md` before changing the widget, themes, usage details, or settings UI.
4. Read `docs/STABILITY.md` before changing refresh, update, login, shutdown, settings persistence, or diagnostics behavior.
5. Run `git status --short` and preserve unrelated work. The repository may intentionally contain uncommitted design work.
6. Read the complete XAML and code-behind for every affected window before editing.
7. Do not commit, push, tag, publish a GitHub release, or replace release artifacts unless the user explicitly asks.

## UI ownership

- `ThemeResources.xaml`: shared semantic brushes, reusable control styles, progress styles, scrollbars, and interaction states.
- `ThemeManager.cs`: theme resource values and theme capability decisions.
- `UsageWidgetWindow.xaml(.cs)`: WPF element visibility, state binding, interaction, and screen positioning.
- `WidgetLayoutCalculator.cs`: the single source of truth for widget width, height, and service-dependent spacing.
- `TraySettings.cs`: persisted settings and service-resolution policy.
- `UsageDetailsWindow.xaml(.cs)`: expanded usage view. Do not assume widget-only visual rules also belong here.

Do not duplicate widget size formulas in a window or controller. Extend `WidgetLayoutRequest` and `WidgetLayoutMetrics` when a new layout input is required.

## Required widget invariants

- Validate Claude-only, Codex-only, both, and neither-available states.
- Validate Small, Compact, and Comfortable densities in both one-row and two-row layouts.
- Hidden services must leave no column, margin, badge, or provider gap behind.
- Reset credits belong only in the expanded usage details window. Do not add reset-credit text, badges, or reserved space to the always-visible widget.
- Changing density, layout, auto-detected services, or progress visibility must preserve a custom top-left position. Default placements must remain anchored to the selected right edge.
- Displayed percentages and progress geometry must use the same clamped value.
- Missing data uses `--%`; it must never reuse a stale percentage with a zero-length bar.
- Keep Korean labels readable and unclipped at the smallest supported dimensions.
- The opt-in `InTaskbar` placement uses dedicated geometry from the `WidgetLayoutCalculator` taskbar branch (`WidgetLayoutRequest.InTaskbar`, `TaskbarLayoutMetrics`). It is independent of density, row layout and visual theme, must fit every taskbar band of at least `MinimumTaskbarBandHeight`, and is never draggable or converted to `Custom`.
- When `TaskbarTracker` reports `Fallback`, show the ordinary floating `TaskbarRight` widget and keep the saved placement `InTaskbar`. Only `Suppressed` (fullscreen or taskbar settling) may hide the widget, and it must be shown again afterwards. These are the only exceptions to the always-visible behavior.
- Never `SetParent`, set an Explorer owner (`GWLP_HWNDPARENT`, `WindowInteropHelper.Owner`), `AttachThreadInput`, inject, use `SetWindowBand`/uiAccess, or send/post messages to Explorer windows. The raise above a covering taskbar is the scoped z-order exception described in `docs/STABILITY.md`. The tracker's only call into Explorer is `SHAppBarMessage(ABM_GETSTATE)` (internally a synchronous `WM_COPYDATA` to `Shell_TrayWnd`); keep it on the single thread-pool worker with the 2 s timeout described there and never call it on the dispatcher.
- Placement code converts device pixels (WinForms `Screen`, Win32 rectangles) to DIPs before assigning `Left`/`Top`.

## Validation

Documentation-only changes require diff, local-link and whitespace checks; do not claim fresh build or visual evidence. Pure prototype changes use its Node/browser checks, not native acceptance claims. Native WPF changes require the native checks below and the relevant manual matrix.

Parse every changed XAML file as XML, then run:

```powershell
git diff --check
dotnet build -c Release -o C:\tmp\dejavu-build-check
dotnet run --project .\tools\WidgetLayoutProbe\WidgetLayoutProbe.csproj -c Release
```

If a running Dejavu instance locks `bin\Release`, keep it running and use an isolated publish output:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:BaseOutputPath=C:\tmp\dejavu-publish-out\ `
  -o C:\tmp\dejavu-publish
```

Review the state matrix in `docs/WIDGET_UI.md` before handoff. Do not treat a successful build as visual verification.
The WPF layout probe is mandatory for widget geometry changes and must report all 504 combinations with zero clipped cases. Its 180 zero/one-provider comparisons, 72 two-provider split checks, 216 auto-detection equivalence checks and 24 Settings frame states must also report no mismatch. The probe must also print `Taskbar layout matrix: 1512 checked, 0 clipped, 0 over band, 0 mismatched` and `Taskbar tracker transitions: 166 checked, 0 mismatched`. When a settle, fallback or suppression rule in `TaskbarTracker` changes, add a timeline to that matrix and update the expected count here and in `docs/DEVELOPMENT.md`.

## Safety and privacy

- Usage and authentication data stay on the user's PC and are read from the supported local Claude/Codex sources.
- Never log tokens, authorization headers, credential contents, or browser conversations.
- Preserve the single-instance behavior. A second `dejavu.exe` normally activates the existing instance instead of opening another widget.

## Documentation ownership

- This file: repository scope, phase, native ownership and safety.
- `docs/DESIGN_SYSTEM.md` / `docs/ICON_SYSTEM.md`: approved redesign, identity and integration boundaries.
- `docs/WIDGET_UI.md`: current native geometry/interaction; `docs/ARCHITECTURE.md` / `docs/STABILITY.md`: runtime/provider/lifecycle rules.
- `design/prototype/AGENTS.md`: reference editing; `macos/AGENTS.md`: deferred Mac handoff.
- Update the relevant contract with behavior or user decisions. Label evidence by date, platform and native-versus-HTML scope. Never replace native invariants with prototype dimensions.
- `docs/WINDOWS_REDESIGN.md` tracks actual native migration milestones. Settings now uses six destinations; connection actions belong to Connections, not Privacy. New theme renderers, details motion and packaged-icon migration remain separate work. Run the focused Settings matrix in `docs/DEVELOPMENT.md` for shell/control changes.
