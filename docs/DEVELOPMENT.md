# Dejavu development guide

This guide is the reproducible workflow for maintainers and coding agents. Read `ARCHITECTURE.md`, `WIDGET_UI.md`, `STABILITY.md` and the repository `AGENTS.md` before editing behavior.

## Prerequisites

- Windows 11 x64
- .NET 10 SDK compatible with `net10.0-windows`
- PowerShell 7 recommended
- Git
- Velopack CLI 1.2.0 only when producing local installers
- Claude Desktop/Claude Code and Codex Desktop/CLI only when exercising their respective integration paths

The app is self-contained when published, but development builds require the SDK. Do not add credentials, local AppData files, diagnostics or certificates to the repository.

## Repository orientation

Use this reading order for a new task:

1. `AGENTS.md` for repository-wide constraints.
2. `docs/ARCHITECTURE.md` for runtime and provider boundaries.
3. `docs/WIDGET_UI.md` for UI state and geometry contracts.
4. `docs/STABILITY.md` for lifecycle and persistence contracts.
5. The complete XAML and code-behind of every affected window.
6. `CHANGELOG.md`, `PRODUCTIZATION.md` and `RELEASE_CHECKLIST.md` when preparing a release.

## Build and run

Restore and build:

```powershell
dotnet restore .\ClaudeUsageTray.csproj
dotnet build .\ClaudeUsageTray.csproj -c Release
```

Run a development build:

```powershell
dotnet run --project .\ClaudeUsageTray.csproj
```

The application is single-instance. If Dejavu is already running, a second launch signals the first instance to open Settings and then exits. Stop the existing instance before diagnosing an apparent immediate exit.

To avoid a running executable locking normal output, publish to a disposable directory without changing `BaseIntermediateOutputPath`:

```powershell
dotnet publish .\ClaudeUsageTray.csproj -c Release -r win-x64 --self-contained true `
  -o C:\tmp\dejavu-publish
```

Changing WPF's intermediate path while the default `obj` directory exists can cause generated XAML and assembly attributes to be compiled twice. Prefer only `-o` for isolated publish verification.

## Development launch options

The executable accepts these diagnostic UI options:

```text
--settings
--onboarding
--details
--theme=Modern|RetroNight|FluentGlass|TerminalMono|Orbit|PaperInk
--density=Small|Compact|Comfortable
--layout=SingleRow|TwoRows
--services=AutoDetect|ClaudeAndCodex|ClaudeOnly|CodexOnly
```

Example:

```powershell
.\bin\Release\net10.0-windows\win-x64\dejavu.exe `
  --settings --theme=PaperInk --density=Small --layout=TwoRows --services=ClaudeAndCodex
```

Preview arguments override the loaded values for the current process. Treat them as developer aids, not a public command-line compatibility promise.

## Provider test overrides

| Variable | Effect |
|---|---|
| `DEJAVU_CLAUDE_SOURCE=desktop` | Ignore Claude Code credentials and exercise the Desktop history path. |
| `CLAUDE_CONFIG_DIR=<directory>` | Look for `<directory>\.credentials.json` before the default Claude location. |
| `CLAUDE_CODE_PATH=<file>` | Prefer a specific Claude Code executable for login. |
| `DEJAVU_CODEX_SOURCE=desktop` | Skip CLI discovery and use a Codex Desktop bundled candidate. |
| `CODEX_CLI_PATH=<file>` | Prefer a specific runnable native Codex executable. |

Set overrides only in the shell used for the test. Do not delete or rename real Claude/Codex credentials to simulate missing state.

## Structural validation

Before handoff, run all checks relevant to the change:

```powershell
$changedXaml = git diff --name-only -- '*.xaml'
foreach ($file in $changedXaml) {
    [xml](Get-Content -LiteralPath $file -Raw) | Out-Null
}

git diff --check
dotnet build .\ClaudeUsageTray.csproj -c Release
```

For widget changes, exercise the matrix in `WIDGET_UI.md`: four service states, three densities, two layouts, progress on/off, all six themes, provider error/loading states and all placement modes. Verify that text and progress geometry use the same percentage.

For lifecycle changes, exercise first start, second-instance activation, forced refresh during a refresh, settings/details open-close, Win+L/unlock, sleep/resume, Explorer restart, RDP/display transitions and tray exit. Confirm topmost recovery does not steal foreground focus or change widget geometry. For Claude file-access changes, confirm Claude Desktop files are opened read-only and handles are released before parsing or network work.

## Manual data-path tests

### Claude

1. Claude Code credential available: verify 5-hour, weekly and account-provided Fable values.
2. `DEJAVU_CLAUDE_SOURCE=desktop`: verify recent Desktop 5-hour/weekly values and unavailable Fable/reset data.
3. No valid source: verify login/setup guidance without a crash or stale percentage/zero-bar mismatch.
4. Rate limit and offline paths: verify previous valid values remain while status communicates retry/offline state.

### Codex

1. Native CLI path and Desktop bundled path: verify `account/rateLimits/read` returns the same displayed structure.
2. Logged-out state: verify the user-triggered browser login and post-login forced refresh.
3. Missing executable: verify the official installation link and no orphan child process.
4. Exit during login/refresh: verify only Dejavu's child `app-server` is terminated.

## Settings and diagnostics

Development runs use the same `%LocalAppData%\dejavu` directory as installed builds. Back up `settings.json` before destructive migration testing. Diagnostics may contain percentages and geometry but must never contain tokens, authorization headers, credential JSON or conversation text.

Use uninstall cleanup tests only with an isolated Windows account or after explicitly backing up Dejavu settings. The cleanup intentionally removes both current and legacy Dejavu data directories.

## Update testing

Do not claim the update path works from a plain publish directory. Velopack's `IsInstalled` must be true.

Test these separately from an installed build:

1. Current version: inline Settings result, no decision window.
2. New version: themed decision window with release notes.
3. Download progress and cancellation.
4. Network/download failure.
5. Apply, restart and retained user settings.
6. Complete uninstall, including startup registration and Dejavu data cleanup while preserving Claude/Codex data.

## Local release packaging

Project version and changelog heading must match. Read the version from the project to avoid stale commands:

```powershell
$version = ([xml](Get-Content .\ClaudeUsageTray.csproj -Raw)).Project.PropertyGroup.Version
.\tools\BuildRelease.ps1 -Version $version
```

To seed delta generation from GitHub Releases:

```powershell
$version = ([xml](Get-Content .\ClaudeUsageTray.csproj -Raw)).Project.PropertyGroup.Version
.\tools\BuildRelease.ps1 -Version $version -DownloadPrevious
```

The script publishes the self-contained app, creates Velopack packages and setup executables, copies the stable `dejavu-Setup.exe` alias and writes `SHA256SUMS.txt`. Generated `bin`, `obj`, `outputs`, publish directories, certificates and local diagnostics must not be committed.

For an actual release, update the project version, `CHANGELOG.md`, public-version references and checklist first. Tag pushes trigger `.github/workflows/release.yml`. Verify the workflow conclusion, target commit, prerelease flag, direct setup asset, update feed, delta/full packages and checksums.

## Common failure modes

| Symptom | First checks |
|---|---|
| Process exits immediately | Another instance may own the mutex; the existing instance should open Settings. Check `%LocalAppData%\dejavu\crash.log`. |
| Duplicate generated WPF types/assembly attributes | Remove disposable build outputs and use the default `obj` path; do not redirect `BaseIntermediateOutputPath` into a second generated tree. |
| Settings or update window appears to close the app | Confirm `ShutdownMode.OnExplicitShutdown`, `Closing` cancellation and `AllowClose` handling. |
| Claude shows login required | Check credential discovery, token expiry and then recent Desktop history; do not inspect or print token contents. |
| Fable is unavailable | Desktop history does not contain Fable; a valid Claude Code account response must expose that scoped limit. |
| Codex is unavailable | Verify a runnable native executable and `app-server`; WindowsApps aliases are intentionally excluded. |
| Update check says installed version required | Expected for `dotnet run`, publish and portable builds. Install through Velopack for update testing. |
| Widget shifts after a layout change | Geometry belongs in `WidgetLayoutCalculator`; custom and right-edge placements have different anchoring rules. |

## Change and commit discipline

- Preserve unrelated changes and stage explicit paths only.
- Keep provider integration changes separate from visual-only changes where practical.
- Update the relevant contract document in the same change as behavior.
- Do not commit, push, tag or release unless the user explicitly authorizes that exact action.
- A successful build is structural evidence, not a substitute for the user's visual review.
