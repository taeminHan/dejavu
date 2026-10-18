# dejavu productization status

기준 버전: `0.9.7` (2026-10-17)

이번 릴리스는 Windows 앱·트레이·설치 파일·바로가기와 제품 헤더 로고 통일 및 실제 패키지/설치 결과의 아이콘 검증을 포함합니다. macOS 기능은 0.9.6과 같고 통합 릴리즈 버전만 맞춥니다. 아래 P0 항목이 해결되기 전에는 공인 서명되거나 Apple 공증된 설치 프로그램으로 표시하지 않습니다.

## Release priorities

### P0 — signed/trusted distribution blockers

1. Replace or formally approve the undocumented usage-data integration.
   The current implementation reads Claude Code's local OAuth credential and calls an endpoint that is not documented as a public third-party API.
2. Add a signed installer, publisher identity, clean upgrade/uninstall behavior, and artifact provenance.
3. Complete a security review covering credential access, redacted diagnostics, proxy behavior, and dependency/update supply chain.
4. Define a compatibility contract for missing limits, renamed models, expired sessions, API throttling, and offline use.

### P1 — public beta experience

1. One-minute first-run flow with an explicit local-data disclosure.
2. Always-on widget with clear loading, ready, login-required, rate-limited, and offline states.
3. Consistent component styling for toggles, dropdowns, sliders, navigation, focus, hover, and disabled states.
4. Persistent position, opacity, density, progress-bar, refresh, tray, startup, and theme preferences.
5. Multi-monitor placement, DPI awareness, keyboard access, and recoverable position reset.

### P2 — 1.0 general availability

1. Validate automatic updates, failed-download recovery, and rollback behavior on clean Windows 11 environments.
2. Korean and English localization.
3. Opt-in crash reporting and a user-exportable redacted diagnostics bundle.
4. Accessibility audit, Windows high-contrast validation, and screen-reader labels.
5. Support, privacy, trademark, license, and release-note pages.

## Implemented in this release

- Windows Familiar Paradox product identity across packaged EXE/setup/stubs/shortcuts, theme-independent product headers and light/dark/high-contrast-aware tray marks; percentage/hidden preferences retained.
- Fail-closed packaged-resource and isolated Windows installation/shortcut acceptance, with a draft-only release workflow and a separate final publication decision after downloaded-asset review.
- macOS menu-bar-first native settings/details, official login flows, explicit previous Claude sign-in reuse and independent extended-access consent.
- macOS cancellation-safe identity switching, bounded refresh recovery, consent-revoking local reset and observed updater availability.
- Windows authoritative Codex bucket parsing, malformed-Claude-credential Desktop fallback, timeout-bounded Codex cancellation drain, corrected theme resources and consistent accent defaults.
- Six-destination native Windows Settings: Display, Appearance, Connections, Behavior, Updates and Privacy.
- Retro Night bitmap lettering, stepped pixel frames/rings and square-cell widget/detail gauges.
- Orbit ordering from Venus to Saturn, preserving separate widget systems and combined solar details.
- Fable-specific response mapping with synthetic parser regression coverage; no Opus/Sonnet substitution.
- WPF product shell replacing the prototype WinForms UI.
- Compact always-on widget and a richer details panel.
- First-run onboarding and credential-presence check.
- Automatic native Windows Claude Code discovery through `CLAUDE_CODE_PATH`, `CLAUDE_CONFIG_DIR`, known native/npm locations, and `PATH`.
- One-click official Claude login launch with three-second completion detection; users never paste a token into dejavu.
- Read-only Codex usage and rate-limit reset-credit display through the official local Codex app-server.
- shadcn-inspired settings layout and styled dropdown content.
- Explicit application states and last-known-value behavior.
- Existing `%LocalAppData%\\ClaudeUsageTray\\settings.json` migration.
- Multi-monitor position clamping and native topmost recovery after display, session, power and Explorer transitions.
- Safe diagnostics that never write OAuth tokens.
- Velopack-based per-user installation and GitHub Releases update checks.
- In-app update download, apply, restart, and opt-out startup plus on-the-hour checks with per-version notification deduplication.

## Deferred or externally blocked

- Trusted code-signing certificate, telemetry, localization, and public-store packaging.
- A supported Anthropic usage API or explicit approval for the current integration.
- Codex Windows Store-only CLI discovery where package ACLs prevent direct child-process execution.
- A cleared trademark and trusted code-signing publisher identity.
