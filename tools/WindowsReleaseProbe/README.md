# Actual Windows release acceptance

This dependency-free .NET probe reads the files that will be distributed. It does
not launch the product or inspect credentials, settings, conversations or accounts.

```powershell
dotnet run --project tools/WindowsReleaseProbe/WindowsReleaseProbe.csproj -c Release -- `
  --source-root $PWD --release-dir C:\temporary\release --version 0.9.7 `
  --output C:\temporary\icon-evidence
```

`--publish-dir` additionally checks the published application; `--installed-root`
checks an installation's root stub, `Update.exe` and `current/dejavu.exe`.
Without either optional directory the approved SVG/ICO provenance still runs.

The gate checks:

- Production SVGs are byte-identical to the approved Familiar Paradox references.
- The generation manifest covers the three app/tray ICOs, source hashes and all
  nine PNG frames (16, 20, 24, 32, 40, 48, 64, 128 and 256 pixels).
- An independent PNG decoder checks the exact approved opaque palette and transparent
  background at 64/256 pixels, rather than trusting a self-consistent hash manifest.
- The old 0.9.6 blue application ICO is explicitly rejected.
- Every RT_GROUP_ICON and referenced RT_ICON in both Setup aliases, published
  application, full nupkg application/execution stub/updater, and portable
  application/stub/updater matches every approved application ICO frame. Extra
  or unreferenced stale icon resources fail the gate.
- An in-memory altered-frame regression fixture must be rejected too.
- Setup aliases are identical, and the full package's version matches the source.

`tools/TestWindowsRelease.ps1` is deliberately restricted to disposable GitHub
Windows runners. It silently installs the real Setup into a new runner-temp
directory, reads the real installer-created Start Menu shortcut and uninstall
registration, verifies all installed PE frames, and asks the shell to resolve the
actual shortcut icon. The shell image is compared with the approved size, allowing
only two premultiplied-alpha channel levels for raster round-tripping.

The pinned Velopack 1.2.0 implementation creates Start Menu shortcuts targeting
`current/dejavu.exe`, with no arguments and icon index zero. `current` is a stable
update directory, not a version-specific `app-0.x.y` path. Its root execution stub
is verified separately. Do not rewrite the test to assume a shortcut targets
`Update.exe` or the root stub based on another Velopack version's behavior.

The installed executable then runs `--validate-brand=<new-empty-directory>`.
That explicit branch precedes the application controller, settings, credential
discovery, providers, updater, single-instance activation and normal UI startup.
It exercises actual embedded resources, 48 synthetic native WPF window trees,
11 tray variants, 13 palettes and a bounded notification-area assignment, producing
a structured report and PNG evidence for review. It does not prove physical DPI
configurations or interactive Explorer/pinned taskbar behavior.

CI uploads the exact packages and evidence before tagging. The tag workflow repeats
acceptance, uploads a **draft** release, downloads the actual uploaded assets,
rechecks their PE/archive icons and matches their hashes with the installed package.
It deliberately does not publish: final artifact and PNG review must precede an
explicit publication action. Never use the presence of a draft or a passing build
as proof that the release was published or visually reviewed.

Both Windows workflows also run `GenerateIcon.ps1` under a separate STA PowerShell
process into a new runner-temp directory and verify it using `--generated-assets`.
WPF and AppKit rasterizers need not produce byte-identical PNG encodings: each must
match its own recorded source/frame hashes, dimensions, transparency and approved
palette. Smoke generation never overwrites the committed production assets, and
generated smoke assets cannot be substituted for packaged-artifact verification.

Upstream contracts used by this gate:

- [Silent install behavior](https://docs.velopack.io/packaging/operating-systems/windows)
- [Setup 1.2.0 arguments](https://docs.velopack.io/reference/cli/content/setup-windows)
- [Pinned shortcut implementation](https://github.com/velopack/velopack/blob/1.2.0/src/bins/src/windows/shortcuts.rs)
- [Pinned current executable locator](https://github.com/velopack/velopack/blob/1.2.0/src/lib-rust/src/locator.rs)
- [Pinned uninstall registration](https://github.com/velopack/velopack/blob/1.2.0/src/bins/src/windows/registry.rs)
