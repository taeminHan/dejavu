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

`claude-desktop-history.schema.json` describes the read-only subset of Claude
Desktop's local `plan-usage-history.json` (`~/Library/Application Support/Claude`
on macOS, `%AppData%\Claude` on Windows). Claude Desktop owns and rewrites this
file about every 15 minutes while it runs; clients copy it into memory, close it
before parsing, and never write, lock, or delete it. Its format is not a
documented integration contract.

- Only `samples[].t` (epoch milliseconds) and `samples[].u.fh` / `u.sd`
  (five-hour and seven-day used percentages) are read. `org` and every other
  key are ignored and never decoded, stored, or logged.
- Malformed samples are skipped. The sample with the greatest `t` wins even
  when the array is unordered; if that sample has neither `fh` nor `sd`, the
  history is unusable rather than falling back to an older sample.
- The history has no reset times and no Fable value. A sample's values are
  accepted for 40 minutes after `t` and up to 2 minutes ahead of the system
  clock. Desktop can skip samples for longer than that while it runs, so on
  macOS an older sample keeps the Claude slot with every value `--%` and the
  sample time until it is 7 days old.
- macOS uses the history when the opt-in extended connection (when enabled)
  and the status-line bridge snapshot have no current data, or when its sample
  is newer than a status-line snapshot captured more than 15 minutes ago.

Fixtures: `claude-desktop-history-recent.json` (unordered samples with an
unknown `xu` key), `claude-desktop-history-lossy.json` (malformed samples mixed
with valid ones), and `claude-desktop-history-no-usage.json` (latest sample has
only unknown keys). They use the placeholder `synthetic-org` instead of a real
organization identifier. Stale and future-skewed cases use injected clocks
against the recent fixture.

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
