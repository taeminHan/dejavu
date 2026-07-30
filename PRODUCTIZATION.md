# dejavu productization status

기준 버전: `0.9.0-rc.2` 개발 중 (2026-07-30)

이 버전은 기능 완성도를 확인하기 위한 공개 릴리스 후보입니다. 아래 P0 항목이 해결되기 전에는 정식 GA 또는 신뢰된 설치 프로그램으로 표시하지 않습니다.

## Release priorities

### P0 — release blockers

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

### P2 — general availability

1. Validate automatic updates, failed-download recovery, and rollback behavior on clean Windows 11 environments.
2. Korean and English localization.
3. Opt-in crash reporting and a user-exportable redacted diagnostics bundle.
4. Accessibility audit, Windows high-contrast validation, and screen-reader labels.
5. Support, privacy, trademark, license, and release-note pages.

## Implemented in this release candidate

- WPF product shell replacing the prototype WinForms UI.
- Compact always-on widget and a richer details panel.
- First-run onboarding and credential-presence check.
- Automatic native Windows Claude Code discovery through `CLAUDE_CODE_PATH`, `CLAUDE_CONFIG_DIR`, known native/npm locations, and `PATH`.
- One-click official Claude login launch with three-second completion detection; users never paste a token into dejavu.
- Read-only Codex usage and rate-limit reset-credit display through the official local Codex app-server.
- shadcn-inspired settings layout and styled dropdown content.
- Explicit application states and last-known-value behavior.
- Existing `%LocalAppData%\\ClaudeUsageTray\\settings.json` migration.
- Multi-monitor position clamping and display-change recovery.
- Safe diagnostics that never write OAuth tokens.
- Velopack-based per-user installation and GitHub Releases update checks.
- In-app update download, apply, restart, and an opt-out startup check.

## Deferred or externally blocked

- Trusted code-signing certificate, telemetry, localization, and public-store packaging.
- A supported Anthropic usage API or explicit approval for the current integration.
- Codex Windows Store-only CLI discovery where package ACLs prevent direct child-process execution.
- A cleared trademark and trusted code-signing publisher identity.
