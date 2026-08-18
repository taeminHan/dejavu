# Dejavu usage contracts

This directory defines the provider data that the Windows and macOS clients may
share in tests. Every fixture is synthetic and intentionally contains only usage
limits, reset metadata, and protocol framing needed by the parser under test.

Upstream references:

- [Claude Code status-line data](https://code.claude.com/docs/en/statusline)
- [Codex app-server protocol](https://developers.openai.com/codex/app-server)

Never add provider credentials, access or authorization tokens, account or
workspace identifiers, URLs with query strings, working directories, prompts,
transcripts, or conversation content here. Tests scan every fixture for these
fields before decoding it.

## Claude

`claude-status-line.schema.json` describes the narrow subset of Claude Code's
official status-line stdin that the bridge is allowed to read. The real input has
many other fields; the bridge must discard them in memory and must never persist
or log them.

`claude-status-snapshot.schema.json` describes the normalized snapshot written by
the bridge. Version 1 stores its capture and reset times as ISO-8601 strings.
`rate_limits`, `five_hour`, and `seven_day` may each be absent because Claude Code
does not always provide them and exposes the two windows independently.

Consumers apply freshness per window:

- a window whose reset time has passed is unavailable until a newer capture;
- a window without a reset time expires after the configured conservative TTL;
- a capture materially ahead of the system clock is rejected in full.

An absent value is not zero and must be presented as unavailable (`--%`).

`claude-oauth-usage.schema.json` is a synthetic, sanitized contract for the
optional extended Fable connection. Anthropic does not document this response
as a third-party integration API. It must remain disabled by default on macOS,
must never contain credentials, and may only be used after an explicit user
choice. The official status-line bridge remains the default Claude source and
does not claim to provide Fable.

## Codex

`codex-rate-limits.schema.json` describes the response envelope for
`account/rateLimits/read` over the app-server JSONL transport.

Selection is deliberately strict:

1. When `rateLimitsByLimitId` is present, only its exact `codex` entry is used.
2. The legacy `rateLimits` bucket is used only when the multi-bucket view is
   absent.
3. `codex_other` and every other bucket are ignored, even when their window
   durations look useful.

The upstream bucket can contain primary and secondary windows, but Dejavu's
normalized Codex product contract exposes only one weekly-backed percentage.
The primary five-hour value remains fixture input for protocol compatibility;
it must not be projected into application UI, persistence, or WidgetKit shared
snapshots. A missing weekly window is unavailable (`--%`), never zero and never
replaced by the primary window.

The upstream bucket shape is preserved exactly in fixtures and schema, including
both `primary` and `secondary` windows. Dejavu exposes only the weekly Codex
window (7 days or longer) as its single product usage value. Shorter windows are
decoded for protocol compatibility but are never copied into the normalized
Codex snapshot, diagnostics, menu bar, overlay, or widgets.

`rateLimitResetCredits.availableCount` is the authoritative count. Detail rows
are optional and possibly capped; they may provide the earliest known expiry but
must never be counted to derive or replace `availableCount`.
