# Prototype test instructions

Applies to this directory, in addition to the repository and prototype instructions.

- These are dependency-free Node checks, not browser automation or native application probes. Keep them runnable with `node <script>.cjs` from the prototype directory.
- `check-theme-renderer.cjs` executes `themes.js` in an isolated VM. It currently checks 40 numerical cases (five Windows themes, eight values), exact pencil clipping, terminal markup, Orbit exclusion, font license presence and selected source whitespace.
- `check-motion.cjs` executes `motion.js` against controlled DOM/media/animation stubs. It checks target clipping, skipped zero/unknown fills, cancellation/reopening, motion off, system preference priority and reduced-transparency state. It does not measure real browser timing, rendered pixels or native system preferences.
- When adding or changing a renderer/theme, extend assertions for the relevant contract. Do not remove failed assertions or rewrite expected values merely to obtain a passing result; diagnose the mismatch first.
- A deliberately failing assertion must produce a nonzero exit code. Preserve actionable output. If the numerical matrix changes, derive/update its reported count and documentation consistently.
- Tests must not access real account/credential files, modify OS/browser settings, open network connections, write production settings, delete user artifacts or start/stop application processes.
- Prefer small deterministic fixtures to external libraries. Preserve the bundled font license check.
- Do not generate browser validation JSON from VM stubs or label unit results as visual QA. Capture browser evidence separately through the supported UI workflow.
- Native WPF layout probes and Mac runtime tests belong in their respective native projects, under those projects' instructions; passing these scripts cannot substitute for them.
