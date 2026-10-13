# Dejavu macOS handoff instructions

Updated: 2026-10-13. Applies here and below, in addition to the repository instructions.

## Current phase: resumed on Mac for implementation and local validation

2026-10-13 release follow-up: the user explicitly authorized the four Windows fixes, Codex cancellation validation and combined Windows/macOS 0.9.6 testing and publication, including the scoped commits/push/tag needed by the existing release workflow. This supersedes the no-publication boundary of the earlier local-only phase below, not the credential/privacy or paid-provisioning restrictions. The user confirmed live Claude usage after selecting the previous Dejavu sign-in. Record Windows CI evidence separately from local Mac validation; do not imply installed update, physical DPI, VoiceOver or App Group acceptance.

On 2026-10-13 the user explicitly resumed missing-feature implementation, prioritized bug fixes and local build/testing on this Mac. Parallel delegation and ad-hoc signing of isolated local test apps were approved. This does not authorize commits, pushes, tags, published releases, replacement of release artifacts, real-account authentication or paid provisioning. Preserve existing Swift/Xcode source, settings and tests.

Approved redesign: menu-bar first, theme-free, macOS 27 direction. Native sidebar settings and attached transient details are now implemented. Existing optional floating/WidgetKit implementations and their saved preferences remain compatible foundations, not permission to remove them. Legacy floating customization is isolated in Advanced settings; it is not applied to the new menu-bar/details design. Minimum deployment remains macOS 14.

## Current runtime and validation ownership

- `AppModel` owns preference loading/saving, bounded refresh scheduling, consent, onboarding completion and auth action state. Reset is a consent-revoking transaction: reject reentrant preference edits and connection/auth actions while it is running.
- `UsageRefreshCoordinator` serializes provider reads, preserves independent statuses and expires carried limits without inventing a new capture time. `UsageRefreshSchedule` uses monotonic deadlines; lifecycle nudges cannot postpone an earlier retry.
- `CodexAuthenticationService` owns official app-server login, completion, cancellation and browser URL lifetime. Stop only Dejavu-owned children. Claude login runs the official `auth login` command in Terminal; no clipboard command handoff or model request.
- Claude configuration paths honor `CLAUDE_CONFIG_DIR`. Connect/disconnect and explicit project preflight are consented reads; startup upgrades only an already-owned bridge. Custom-profile Fable access fails closed rather than guessing a Keychain item.
- `AppSettings.claudeCredentialIdentity` is a user-selected standard/previous-Dejavu-default identity, never credential data. Each reads one exact official service/account with no fallback, enumeration or credential mutation. Selecting a location does not grant extended access. When extended access is enabled, do not fall back to an unscoped status-line snapshot on an identity error.
- An identity change clears Claude values immediately, drains/invalidate older refreshes and resets the OAuth generation/backoff before the new Claude-only read. Preserve settled Codex state and any deferred official-login follow-up. Preferences reset must not redirect a Claude login that is already in progress.
- `AppCoordinator` owns native windows/popover and the synthetic `--validate-ui` route. That route bypasses real settings/providers, login-item mutation, App Group publication and Sparkle startup.
- `tools/RunMacAppModelProbe.sh` compiles the actual app model with injected temporary stores/providers. `tools/RunMacUpdateProbe.sh` checks the actual update coordinator with a synthetic Sparkle transport; it does not prove downloaded-update installation.
- Use isolated scratch/derived-data directories. Record commands, counts, native captures and remaining device/account acceptance checks in `docs/MACOS_DEVELOPMENT.md`; never describe fixture checks as real-account acceptance.

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
