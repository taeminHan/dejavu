# Dejavu editable design reference

Updated: 2026-10-02. Applies here and below, in addition to repository instructions.

## Scope

This is the approved dependency-free HTML/CSS/JS design reference imported from the local design study. It is not the website or a native app. Current work is Windows-only; preserve the Mac reference for later native work on a Mac.

Read `../../docs/DESIGN_SYSTEM.md`, `../../docs/ICON_SYSTEM.md`, and complete affected source before editing. Never claim native implementation/validation from this reference. Do not introduce a framework/build stack or delete old native assets without authorization.

## Ownership and invariants

- `app.js`: sample state, service visibility, placement and interactions. `themes.js` / `themes.css`: Windows forms and deterministic graphs. `platform.css`: frozen, theme-free Mac reference.
- `index.html`, `style.css`, `preview.css`: studio, logical-size OS context and layout. `icons.js`: original action registry. `motion.js`: cancellable opening-only reveal.
- `server.cjs`: explicit static allowlist, loopback only. Do not expose the repository or credentials. All account/usage values are simulated.
- Preserve Orbit's native treatment; it is intentionally absent here. Field Notes keeps Paper Ink handwriting/wavy-pencil character, without memo tabs or new dashed/ledger decoration.
- Credits are details-only. No headers/badge slots in widgets; graph off retains values/padding; one-provider two-row geometry matches one row; equivalent Auto/Both matches.
- Preserve custom positions/edge anchors and click-versus-drag distinction. Taskbar geometry is independent of themes/density/rows and not draggable. Opacity is background-only.
- Mac remains theme-free/menu-bar first and isolated from Windows settings. Do not expand its design/native features during Windows work. Shared changes need only an affected-reference smoke check.
- Percent text, fill and accessibility share clamped values. Unknown differs from zero. Opening animation never changes counts/layout or restarts on unchanged resize; system reduced motion wins.

## Run and check

From the repository root, run `node design/prototype/server.cjs`; it binds `http://127.0.0.1:5184/`. Check for an existing server first. Stop only an instance owned by this task, not unrelated Node processes.

From this directory:

```powershell
node --check app.js
node --check themes.js
node --check motion.js
node --check icons.js
node --check server.cjs
node tools/check-theme-renderer.cjs
node tools/check-motion.cjs
git diff --check
```

Browser-check relevant Windows themes, densities, providers, row/graph/appearance states, positions and keyboard/pointer behavior. Preserve 1:1 logical size; use scrolling/expanded view instead of shrinking to hide clipping. Native WPF checks remain in `../../docs/DEVELOPMENT.md` and `../../docs/WIDGET_UI.md`.

Copied `*-validation.json` files record earlier HTML checks, not a fresh native test or repository import test. Use stable evidence names and no credentials. Do not copy old logo experiments, tar files, outputs or temporary screenshots into this directory. Commit/push/release remains explicitly user-controlled.
