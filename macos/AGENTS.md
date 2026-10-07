# Dejavu macOS handoff instructions

Updated: 2026-10-02. Applies here and below, in addition to the repository instructions.

## Current phase: deferred

The user is developing Windows now and will resume Mac implementation separately on a Mac. Preserve existing Swift/Xcode source and tests. This file does not authorize current Mac development, deletion, scaffolding, builds, signing or releases. Requested documentation-only scope updates are allowed.

Approved redesign: menu-bar first, theme-free, macOS 27 direction. Existing floating/WidgetKit/status-menu implementations are historical foundations, not proof of redesign completion or permission to remove them. Windows completion must not depend on this deferred phase.

## When explicitly resumed on a Mac

1. Inspect the actual checkout, dirty state and root instructions. Do not assume Windows absolute paths, PowerShell, credentials or staging directories exist.
2. Read `docs/DESIGN_SYSTEM.md`, `docs/ICON_SYSTEM.md`, `docs/MACOS_DEVELOPMENT.md`, `docs/MACOS_APPLE_DESIGN.md` and relevant privacy/runtime contracts. Latest user decisions take precedence over older surface plans. HTML evidence is not native evidence.
3. Verify macOS, Xcode/SDK, lockfiles and current official Apple guidance. Confirm minimum OS support and distribution scope; a macOS 27 design target is not automatically a macOS 27-only deployment requirement.
4. Inspect and reuse `DejavuMac.xcodeproj`, `DejavuMac/`, `DejavuClaudeBridge/` and `Packages/DejavuKit/`. Determine completed/partial/obsolete behavior from code/tests before planning changes. Do not create another parallel Mac app by default.
5. Reconcile the existing `StatusItemController`, settings/details/window coordinators and saved preferences with menu-bar-first presentation. Use standard SwiftUI/AppKit controls/materials, not WPF templates or CSS dimensions. Removal/migration of old floating or WidgetKit features needs an explicit scoped decision.
6. Validate providers independently on Mac. Read adapters/fixtures before detection/authentication changes. Never copy Windows credentials or assume Desktop/CLI behavior is identical. Real connection/configuration changes require consent; synthetic fixtures contain no secrets/conversations.
7. Confirm `docs/MACOS_DEVELOPMENT.md` commands/toolchain on this machine before running them. Core fixtures, compilation, real UI and installed update tests are separate evidence. Windows tests cannot establish native Mac behavior.
8. Record native evidence and update this file with actual architecture, commands and limitations. Signing, notarization, entitlements, keys, release workflows and publication require their own authorization.

## Approved UI invariants

- No product themes, themed graphs, desktop-widget counterpart, density/row/topmost controls or product opacity slider in the new direction. Keep Windows theme settings isolated.
- Monochrome status item and percentages; system appearance by default; attached details with reachable settings/refresh actions, repeated-click/outside/Esc dismissal and keyboard focus handling.
- Semantic colors, system typography, actual functional SF Symbols and accessible native controls. CSS blur is not native Liquid Glass. Honor Reduce Motion/Transparency and increased contrast.
- Text, graphs and accessibility share a normalized value; unknown/expired differs from zero. Named credits and expiry are details-only.
- Verify light/dark/system, 0/1/2 providers, missing/stale/partial/error states, keyboard/VoiceOver, Retina/multiple displays and panel attachment on a real Mac.
- Preserve local privacy boundaries and terminate only Dejavu-owned children. Do not scrape conversations, print tokens or copy credentials into fixtures/artifacts.
