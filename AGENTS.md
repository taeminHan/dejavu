# Dejavu contributor instructions

These instructions apply to the entire repository. Dejavu is a public Windows 11 WPF product, not a developer-only tray utility. Preserve existing user settings, local-only data handling, and the always-visible widget behavior.

## Start here

1. Read `docs/WIDGET_UI.md` before changing the widget, themes, usage details, or settings UI.
2. Read `docs/STABILITY.md` before changing refresh, update, login, shutdown, settings persistence, or diagnostics behavior.
3. Run `git status --short` and preserve unrelated work. The repository may intentionally contain uncommitted design work.
4. Read the complete XAML and code-behind for every affected window before editing.
5. Do not commit, push, tag, publish a GitHub release, or replace release artifacts unless the user explicitly asks.

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

## Validation

Parse every changed XAML file as XML, then run:

```powershell
git diff --check
dotnet build -c Release -o C:\tmp\dejavu-build-check
```

If a running Dejavu instance locks `bin\Release`, keep it running and use an isolated publish output:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true `
  -p:BaseOutputPath=C:\tmp\dejavu-publish-out\ `
  -o C:\tmp\dejavu-publish
```

Review the state matrix in `docs/WIDGET_UI.md` before handoff. Do not treat a successful build as visual verification.

## Safety and privacy

- Usage and authentication data stay on the user's PC and are read from the supported local Claude/Codex sources.
- Never log tokens, authorization headers, credential contents, or browser conversations.
- Preserve the single-instance behavior. A second `dejavu.exe` normally activates the existing instance instead of opening another widget.
