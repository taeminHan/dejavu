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
--progress=on|off
--placement=TaskbarRight|TopRight|Custom|InTaskbar
```

Example:

```powershell
.\bin\Release\net10.0-windows\win-x64\dejavu.exe `
  --settings --theme=PaperInk --density=Small --layout=TwoRows --services=ClaudeAndCodex --progress=off

.\bin\Release\net10.0-windows\win-x64\dejavu.exe --placement=InTaskbar --services=ClaudeAndCodex
```

Preview arguments are applied to the in-memory settings at startup and are not written by themselves. Any later save in that session writes them to `%LocalAppData%\dejavu\settings.json`: a Settings change, Reset position, a Custom move, onboarding completion, or a new-version notification. Restore the value in Settings afterwards if needed. Exit the running tray instance first: a second `dejavu.exe` only opens Settings in the existing instance and ignores its arguments. Outside a preview, the in-taskbar placement is turned on in Settings → 동작 → 기본 표시 위치 → 작업표시줄 안 · 시계 옆. Treat preview arguments as developer aids, not a public command-line compatibility promise.

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
dotnet run --project .\tools\WidgetLayoutProbe\WidgetLayoutProbe.csproj -c Release
```

For widget changes, the layout probe must pass all 504 combinations of seven forced/auto-detected service states, three densities, two layouts, progress on/off and all six themes. It loads and arranges the actual WPF tree, fails when `WidgetCard.DesiredSize.Height` exceeds the calculated window height, compares 180 zero/one-provider pairs to ensure `TwoRows` is visually identical to `SingleRow`, verifies 72 two-provider splits including Codex-above-Claude order, compares 216 auto-detected states with their forced-provider equivalents, and checks that the Codex 5-hour and weekly labels do not overlap their values. It also checks 24 Settings frame states across all visual themes, light/dark preferences and normal/maximized modes. Finally it docks a synthetic taskbar band for the same 504 axes at 32, 40 and 48 DIP and must print `Taskbar layout matrix: 1512 checked, 0 clipped, 0 over band, 0 mismatched`; failures are written to standard error with a `TASKBAR` prefix and make the exit code non-zero. It runs at the machine's system DPI, so repeat it at 125 % and 150 % after changing taskbar geometry: change the scale, then start a new probe process. It then replays `TaskbarTracker` settle timelines with synthetic evaluations and clock readings (hard-fallback confirmation, reason changes, off-cadence evaluations, missing taskbar or tray, stable, unstable and auto-hide-pending geometry, fullscreen, outside-settling resolution and leaving a fallback) without enabling the tracker, and must print `Taskbar tracker transitions: 166 checked, 0 mismatched`. The Codex window variants must print `Codex window variants: 48 checked, 0 mismatched` for weekly-only, 5-hour-only, neither and a carried expired 5-hour window in linear and taskbar placements. Failures use a `TRACKER` or `CODEX WINDOW` prefix. Then exercise provider error/loading states, placement modes and pointer behavior manually. Verify that text and progress geometry use the same percentage.

For lifecycle changes, exercise first start, second-instance activation, forced refresh during a refresh, settings/details open-close, Win+L/unlock, sleep/resume, Explorer restart, RDP/display transitions and tray exit. Confirm topmost recovery does not steal foreground focus or change widget geometry. With `--placement=InTaskbar`, also follow the in-taskbar items of the manual checklist in `WIDGET_UI.md` and read the tracker status, reason and raise counters in `status.json`. For Claude file-access changes, confirm Claude Desktop files are opened read-only and handles are released before parsing or network work.

## Manual data-path tests

### Native Settings redesign probe

Run the focused Settings matrix without starting the controller, saving settings or querying providers:

```powershell
$env:DEJAVU_SETTINGS_ONLY = '1'
try {
    dotnet run --project .\tools\WidgetLayoutProbe\WidgetLayoutProbe.csproj -c Release
} finally {
    Remove-Item Env:DEJAVU_SETTINGS_ONLY
}
```

Expected: `Settings redesign matrix: 144 checked, 0 invalid` and 48 inline update states. The matrix arranges real WPF trees at default/minimum size, checks all six navigation destinations, row overlap, scrolling width, picker label bounds/accessibility names and loading/results. The ordinary probe still checks native window frames, widgets, Orbit and taskbar behavior independently.

Optional `DEJAVU_SETTINGS_PREVIEW=<temporary directory>` writes synthetic WPF PNGs; unset it after the run. These are not installed-app screenshots or physical-DPI/keyboard acceptance. See [WINDOWS_REDESIGN.md](WINDOWS_REDESIGN.md) for current scope and remaining manual checks.

### Retro pixel rendering

For native Retro rendering, run the ordinary full probe or set `DEJAVU_RETRO_ONLY=1` for
`Retro pixel matrix: 144 widget/detail states, 0 failures`. Optional `DEJAVU_RETRO_PREVIEW`
writes sample WPF PNGs. Unset these variables after the test. Font regeneration and licensing
are documented in [README-DejavuPixel.md](../assets/Fonts/README-DejavuPixel.md).

### Claude

Run the pure production-parser regression probe before changing Claude response mapping:

```powershell
dotnet run --project .\tools\ClaudeUsageParserProbe\ClaudeUsageParserProbe.csproj -c Release
```

Expected: `Claude usage parser: 20 checked, 0 failures`. It uses synthetic JSON only and does not launch the app/controller, read credentials, history or settings, or make HTTP requests. Cases cover legacy/modern Fable, zero usage, reset timestamps, precedence, absent/null Fable with Opus/Sonnet present, preserved 5-hour/weekly values and unchanged malformed-response rejection. Other model limits must never be relabeled as Fable. This is parser evidence, not live provider or UI acceptance.

1. Claude Code credential available: verify 5-hour, weekly and account-provided Fable values.
2. `DEJAVU_CLAUDE_SOURCE=desktop`: verify recent Desktop 5-hour/weekly values and unavailable Fable/reset data.
3. No valid source: verify login/setup guidance without a crash or stale percentage/zero-bar mismatch.
4. Rate limit and offline paths: verify previous valid values remain while status communicates retry/offline state.

### Codex

0.9.6의 인증/수집 회귀 검사는 실제 공급자 소스를 연결한 별도 실행 파일로 수행한다. 임시 합성 인증 자료와 이 테스트가 시작한 가짜 app-server만 사용하며 실제 CLI·키체인·계정·사용자 설정·네트워크를 사용하지 않는다.

```powershell
dotnet run --project .\tools\WindowsProviderProbe\WindowsProviderProbe.csproj -c Release
```

예상: `Windows provider regression: 72 checked, 0 failures`. 다중 버킷의 우선순위, malformed 인증의 Desktop fallback, 취소 전 자식 미실행, 진행 중 요청의 완료 표식 보존, 원래 호출자 취소 전달과 실제 15초 timeout을 검사한다. 이전 연결 토큰 패턴이 pending pipe를 즉시 취소하는지는 실행 환경별 결과를 별도로 출력하며, 관찰되지 않은 실패를 재현했다고 주장하지 않는다.

기본 WPF layout probe에는 `Windows theme resource matrix: 36 checked, 0 failures`와 `Windows accent defaults: 5 checked`도 포함된다. 사용자 설정 저장 없이 실제 WPF 상세·시작 안내·업데이트 화면의 배경색과 새 기본값/이전 저장색/기본값 복원을 검사한다.

`DEJAVU_THEME_REGRESSION_PREVIEW=<temporary directory>`를 지정하면 위 테마 검사에서 실제 WPF 트리의 합성 PNG 36개를 저장한다. CI의 `windows-theme-previews` artifact로 내려받아 배경색·대비를 육안 확인한다. 이 이미지는 실제 설치 앱 화면 또는 물리 DPI 검증이 아니다.

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
7. Automatic checks enabled: one startup check and a check at the exact next local clock hour.
8. Automatic checks disabled: no startup, hourly or resume check; manual Settings checks still work.
9. Repeated availability of the same version: one automatic notification across later hours and an app restart; a newer version may notify once again.
10. Notification interaction: clicking the tray notification opens the themed update decision window; a hidden tray uses the decision window once per version.
11. Startup, clock-hour and manual requests that overlap: one network query is shared and the manual UI receives its final result.
12. Sleep/resume and system-time changes: one overdue catch-up at most, no burst for skipped hours, then alignment to the next wall-clock hour.

The scheduler is deliberately based on the next wall-clock boundary, not a fixed one-hour interval. Pure schedule and notification-policy checks may run against a Release build, but notification, install detection, download and apply behavior still require a Velopack-installed build.

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

The script publishes the self-contained app, creates Velopack packages and setup executables, copies the stable `dejavu-Setup.exe` alias and writes `SHA256SUMS.txt`. Before reporting success it runs `tools/WindowsReleaseProbe` over actual app/installer/stub/updater/archive icon resources and rejects missing, stale or altered frames. Generated `bin`, `obj`, `outputs`, publish directories, certificates and local diagnostics must not be committed.

For an actual release, update the project version, `CHANGELOG.md`, public-version references and checklist first. Tag pushes trigger `.github/workflows/release.yml`, which now leaves a **draft**, not a public release. Verify the workflow conclusion, target commit, prerelease flag, downloaded setup asset, update feed, delta/full packages, installed evidence and checksums. Review actual icon PNGs and only then explicitly publish the verified draft. Never overwrite an already published version to hide a packaging error.

### Packaged Windows brand and real installation acceptance

`tools/GenerateIcon.ps1` is the Windows STA/WPF asset generator; `tools/GenerateWindowsIcons.swift` is the equivalent asset tool available on a Mac. Both read the approved production SVGs and record source/frame provenance. Do not regenerate into the source tree during a release: committed reviewed ICO frames are the artifact contract. A generator smoke test must use a new temporary directory.

```powershell
dotnet run --project tools/WindowsReleaseProbe/WindowsReleaseProbe.csproj -c Release -- `
  --source-root $PWD --release-dir C:\tmp\dejavu-release\dejavu-velopack-releases `
  --version 0.9.7 --output C:\tmp\dejavu-icon-evidence
```

The cross-platform read-only verifier compares approved SVGs, provenance hashes and all 27 source frames, then every icon group/frame in the two Setup aliases, full nupkg (app/execution stub/updater/setup ICO), portable archive and, when supplied, installed binaries. It includes a negative altered-frame fixture; a build-only or single shell-icon check is insufficient.

`tools/TestWindowsRelease.ps1` deliberately refuses normal developer accounts and requires an ephemeral GitHub Windows runner. It installs the actual Setup silently into a new `RUNNER_TEMP` directory without launching the normal application, verifies the real Start Menu shortcut, shell-resolved icon pixels and Apps & Features registration, and invokes the installed executable's `--validate-brand=<absolute empty output directory>` path. That path precedes Velopack, mutex activation and the controller, uses in-memory fixtures, and never loads/saves user settings, authenticates, queries providers or starts the updater. Its 48 WPF window/11 tray/13 fixed-palette cases and generated JSON/PNGs are **synthetic native resource evidence**, not interactive Explorer or physical-DPI acceptance.

CI saves `windows-release-candidate` and `windows-release-acceptance` artifacts. A separate clean Windows runner executes `TestWindowsUpgrade.ps1`: checksum-verified public 0.9.6 installation and legacy-logo preconditions, then SDK-equivalent updater preparation and real `Update.exe --silent apply --norestart`. For 0.9.7, both workflows seed delta creation from the explicitly pinned public 0.9.6 package, not the changing latest release. The upgrade gate requires that delta, restores it with the real updater's `patch` command, rejects duplicate ZIP paths and compares every entry's type and uncompressed SHA-256 with the verified original full package before applying the restored package. ZIP archive bytes need not be identical after recompression; both archive hashes are recorded separately. Fresh installation uses the original full package, so both package paths are covered. All three executable icons and the existing shortcut are checked again; its evidence is `windows-upgrade-acceptance`. This is not the full in-app download/restart GUI path. Future versions retain the fixed-baseline full-package logo regression but must deliberately update or add their own delta-baseline acceptance; the 0.9.7 delta evidence does not cover future deltas.

The tag workflow also attaches `Windows-release-verification.zip` to the draft, redownloads its actual Windows release files and verifies their resources and hashes against the package that passed installation. Its separate `windows-upgrade` job then exercises that actual downloaded draft package. **Wait for the whole workflow, including upgrade acceptance**, before final artifact/PNG review and explicit publication. Physical Windows 11 DPI, pinned icon/cache refresh, screen-reader and in-app automatic-update GUI acceptance remain explicitly separate.

Velopack 1.2.0 regenerates `RELEASES` and `releases.win.json` when uploading. Their BOM, line endings and JSON formatting are not binary-package identity: verify the feed's exact version/package/file/type and actual SHA1/SHA256/size, while retaining byte-identical checks for installers, Portable, full and delta binaries. The 0.9.7 draft recovery workflow preserves the original product tag, checks out that exact product separately from validation control code, completes the actual draft's checksums and repeats real fresh installation and delta migration on separate disposable Windows runners. It never publishes; the earlier failed run remains part of the audit trail.

## Common failure modes

| Symptom | First checks |
|---|---|
| Process exits immediately | Another instance may own the mutex; the existing instance should open Settings. Check `%LocalAppData%\dejavu\crash.log`. |
| Duplicate generated WPF types/assembly attributes | Remove disposable build outputs and use the default `obj` path; do not redirect `BaseIntermediateOutputPath` into a second generated tree. |
| Settings or update window appears to close the app | Confirm `ShutdownMode.OnExplicitShutdown`, `Closing` cancellation and `AllowClose` handling. |
| Claude shows login required | Check credential discovery, token expiry and then recent Desktop history; do not inspect or print token contents. An expired token with a refresh token shows `Claude 토큰 갱신 대기` instead (run Claude Code once), and Desktop without a recent sample shows `Claude Desktop 기록 대기`; `claudeIssue` in `status.json` names both. |
| Fable is unavailable | Desktop history does not contain Fable; a valid Claude Code account response must expose that scoped limit. |
| Codex is unavailable | Verify a runnable native executable and `app-server`; WindowsApps aliases are intentionally excluded. |
| Update check says installed version required | Expected for `dotnet run`, publish and portable builds. Install through Velopack for update testing. |
| Widget shifts after a layout change | Geometry belongs in `WidgetLayoutCalculator`; custom and right-edge placements have different anchoring rules. |
| Widget is off-screen or misplaced above 100 % scaling | A device-pixel rectangle was assigned to WPF `Left`/`Top` without `TransformFromDevice`. |
| In-taskbar widget floats instead of docking | Expected for `Fallback`. Check the tracker reason in `status.json` (`non_xaml_taskbar`, `vertical`, `autohide`, `rtl_or_mirrored`, `band_too_small`, `shell_mismatch`, `taskbar_missing`, `tray_missing`). |
| In-taskbar widget disappears | Expected while `Suppressed`: `fullscreen`, or `settling` after startup, Explorer restart, display change, resume/unlock or leaving a fallback (a hard fallback such as `non_xaml_taskbar` appears about 2 s after settling began). |

## Change and commit discipline

- Preserve unrelated changes and stage explicit paths only.
- Keep provider integration changes separate from visual-only changes where practical.
- Update the relevant contract document in the same change as behavior.
- Do not commit, push, tag or release unless the user explicitly authorizes that exact action.
- A successful build is structural evidence, not a substitute for the user's visual review.
