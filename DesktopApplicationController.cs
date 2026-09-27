using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using Velopack;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace ClaudeUsageTray;

internal sealed class DesktopApplicationController : IDisposable
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "dejavu";
    private static readonly TimeSpan LoginWatchDuration = TimeSpan.FromMinutes(5);
    // A Claude 429 waits for Retry-After, clamped so a missing, tiny or huge header neither hammers
    // the endpoint nor blocks it for long.
    private static readonly TimeSpan MinimumClaudeRetryDelay = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan MaximumClaudeRetryDelay = TimeSpan.FromMinutes(30);
    // Early retries after a transient provider failure, before the normal interval takes over.
    private static readonly TimeSpan[] TransientRetryDelays = [TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(30)];
    // Resume, unlock and a returning network move the next periodic refresh this close.
    private static readonly TimeSpan SoonRefreshDelay = TimeSpan.FromSeconds(5);
    // Velopack's check takes no token and its HTTP client waits up to 30 minutes.
    private static readonly TimeSpan UpdateCheckTimeout = TimeSpan.FromSeconds(60);
    // Velopack reports download progress in 3 % steps; no step for this long means a dead connection.
    private static readonly TimeSpan UpdateDownloadStallTimeout = TimeSpan.FromMinutes(10);
    private const string ClaudeRateLimitedMessage = "Claude 자동 재시도";
    private const string ClaudeEndpointChangedMessage = "Claude 사용량 응답 변경";
    private readonly System.Windows.Application _application;
    private readonly TraySettings _settings = TraySettings.Load();
    private readonly ClaudeUsageClient _claudeClient = new();
    private readonly CodexUsageClient _codexClient = new();
    private readonly UsageWidgetWindow _widget;
    private readonly UsageDetailsWindow _details = new();
    private readonly SettingsWindow _settingsWindow;
    private readonly OnboardingWindow _onboarding;
    private readonly UpdateWindow _updateWindow = new();
    private readonly VelopackUpdateService _updateService = new();
    private readonly Forms.NotifyIcon _trayIcon = new();
    private readonly DispatcherTimer _timer = new();
    private readonly DispatcherTimer _loginWatchTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly DispatcherTimer _automaticUpdateTimer = new();
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly TaskbarTracker _taskbarTracker;
    private CancellationTokenSource? _refreshCancellation;
    private CancellationTokenSource? _updateCancellation;
    private CancellationTokenSource? _codexLoginCancellation;
    private UpdateInfo? _pendingUpdate;
    private Task<UpdateCheckResult>? _updateCheckTask;
    private DateTimeOffset? _nextAutomaticUpdateAt;
    private DateTimeOffset _loginWatchUntil;
    // Environment.TickCount64 (ms, the clock of _refreshDueTick) until which periodic and login-watch
    // refreshes make no Claude request after a 429, unless the credential file changed (a new login or
    // token refresh) since the 429. A system clock change neither stretches nor shortens the wait.
    private long? _claudeRetryDueTick;
    private (DateTime WriteUtc, long Length)? _claudeRetryCredential;
    private int _transientRetryCount;
    // Environment.TickCount64 (ms) at which the periodic timer next fires. DispatcherTimer also runs on
    // the tick count, so a system clock change does not skew it.
    private long _refreshDueTick;
    private int _forcedRefreshGeneration;
    // Set by an explicit 지금 새로고침 and consumed by the refresh that reads Claude, so it survives the
    // collapse into a newer forced refresh. Only it lets Claude be read before a 429's Retry-After.
    private bool _claudeRetryBypassRequested;
    // The pending Codex browser login's page; a repeated login click reopens it. Never logged.
    private string? _codexLoginAuthUrl;
    private bool _networkChangeSubscribed;
    private ApplicationState _state = ApplicationState.Loading();
    private Drawing.Icon? _generatedIcon;
    private bool _loginWatchRequiresClaudeCode;
    private bool _codexLoginInProgress;
    // The settled Codex LoginRequired came from a missing account (-32600), not a backend 401.
    private bool _codexLoginRequiredAccountMissing;
    // The widget has been asked to appear (first run completed or onboarding closed).
    private bool _widgetRequested;
    // The tracker reports Suppressed: a fullscreen app or a settling taskbar hides the widget.
    private bool _taskbarSuppressed;
    // The widget cancels every close except shutdown; a closed Window can never be shown again.
    private bool _widgetClosed;
    private bool _disposed;

    public DesktopApplicationController(System.Windows.Application application, bool startWithSettings = false,
        bool startWithOnboarding = false, bool startWithDetails = false,
        WidgetVisualTheme? previewTheme = null, WidgetDensity? previewDensity = null,
        WidgetLayout? previewLayout = null, ServiceDisplayMode? previewServices = null,
        bool? previewProgress = null, WidgetPlacement? previewPlacement = null)
    {
        _application = application;
        if (previewTheme is not null) _settings.WidgetTheme = previewTheme.Value;
        if (previewDensity is not null) _settings.WidgetDensity = previewDensity.Value;
        if (previewLayout is not null) _settings.WidgetLayout = previewLayout.Value;
        if (previewServices is not null) _settings.ServiceDisplayMode = previewServices.Value;
        if (previewProgress is not null) _settings.ShowProgressBars = previewProgress.Value;
        if (previewPlacement is not null) _settings.WidgetPlacement = previewPlacement.Value;
        ThemeManager.Apply(_settings);
        _updateWindow.ApplyTheme(_settings.WidgetTheme);
        if (_updateService.IsInstalled) MigrateExistingStartupRegistration();

        _widget = new UsageWidgetWindow(_settings);
        _settingsWindow = new SettingsWindow(_settings)
        {
            StartupStateProvider = IsStartupEnabled
        };
        _onboarding = new OnboardingWindow(_settings);

        WireWindows();
        ConfigureTray();
        ScheduleRefresh(TimeSpan.FromSeconds(_settings.RefreshSeconds));
        _timer.Tick += async (_, _) =>
        {
            if (_disposed) return;
            // The timer repeats with the same interval after each tick.
            _refreshDueTick = Environment.TickCount64 + (long)_timer.Interval.TotalMilliseconds;
            await RefreshAsync();
        };
        _timer.Start();
        _loginWatchTimer.Tick += async (_, _) =>
        {
            if (_disposed) return;
            _onboarding.RefreshDetection();
            // The login watcher must not repeatedly cancel a slow provider request.
            // A non-forced refresh coalesces with one already in progress. It reads only
            // Claude, so it never starts a Codex app-server every tick; Codex is included
            // only while it has never been checked.
            await RefreshAsync(includeCodex: _state.CodexStatus == UsageStatus.Loading);
            if (_disposed) return;
            var connected = _state.ClaudeStatus == UsageStatus.Ready &&
                            (!_loginWatchRequiresClaudeCode ||
                             _state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode);
            if (connected || DateTimeOffset.Now >= _loginWatchUntil) _loginWatchTimer.Stop();
        };
        _automaticUpdateTimer.Tick += OnAutomaticUpdateTimerTick;
        ConfigureAutomaticUpdateChecks();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.TimeChanged += OnSystemTimeChanged;
        // The network nudge is optional. With a broken or restricted Winsock stack the add accessor
        // can throw (SocketException or NetworkInformationException) while starting its listener;
        // resume, unlock and the transient retries still recover, so startup must not fail on it.
        // Nothing is logged.
        try
        {
            NetworkChange.NetworkAvailabilityChanged += OnNetworkAvailabilityChanged;
            _networkChangeSubscribed = true;
        }
        catch (Exception)
        {
        }
        // Must exist before the first ShowWidget below. Nothing earlier in this constructor
        // dereferences it: WireWindows and ConfigureTray only register handlers, and the
        // SystemEvents handlers reach the tracker only through dispatcher work, which cannot
        // run until this constructor has returned.
        _taskbarTracker = new TaskbarTracker(_application.Dispatcher);
        _taskbarTracker.StateChanged += OnTaskbarStateChanged;
        // Forward every request: the widget applies its own visibility, dock, raise-block and
        // rate-limit checks. The tracker raises these only while Docked (the widget is then
        // shown); a hidden widget's raise block is lifted by the "docked" check that follows
        // the next show, or by the backstop once the foreground window has changed.
        _taskbarTracker.RaiseRequested += (_, reason) =>
        {
            if (!_disposed) _widget.RaiseAboveTaskbarIfCovered(_taskbarTracker.TaskbarHandle, reason);
        };

        if (startWithDetails)
        {
            ShowWidget();
            ToggleDetails();
        }
        else if (startWithSettings)
        {
            ShowWidget();
            ShowSettings();
        }
        else if (startWithOnboarding)
        {
            _onboarding.Show();
            _onboarding.Activate();
        }
        else if (_settings.FirstRunCompleted) ShowWidget();
        else
        {
            _onboarding.Show();
            _onboarding.Activate();
        }

        _ = RefreshAsync();
        if (_settings.AutomaticUpdateChecksEnabled) _ = CheckForUpdatesAfterStartupAsync();
    }

    private void WireWindows()
    {
        _widget.WidgetClicked += (_, _) => ToggleDetails();
        _widget.SettingsRequested += (_, _) => ShowSettings();
        _widget.PositionChangedByUser += (_, _) => _settings.Save();
        _widget.Closed += (_, _) => _widgetClosed = true;

        _details.RefreshRequested += async (_, _) => await RefreshAsync(force: true, bypassClaudeRetry: true);
        _details.SettingsRequested += (_, _) => ShowSettings();
        _details.ClaudeLoginRequested += (_, _) => StartClaudeLogin(requireClaudeCode: true);
        _details.CodexLoginRequested += async (_, _) => await StartCodexLoginAsync();

        _settingsWindow.SettingsChanged += (_, _) => ApplySettings();
        _settingsWindow.PositionResetRequested += (_, _) =>
        {
            _widget.PositionFromSettings(forceDefault: true);
            if (_settings.WidgetPlacement != WidgetPlacement.Custom) return;
            // Switching to Custom shows the default point; save it so the saved custom point
            // matches the screen and a later settings change or restart does not move the widget.
            _widget.KeepCurrentPositionVisible();
            _settings.Save();
        };
        _settingsWindow.StartupChanged += (_, enabled) =>
        {
            SetStartup(enabled);
            // SetStartup swallows registry failures; show the value that was really written.
            _settingsWindow.RefreshStartupState();
        };
        _settingsWindow.UpdateCheckRequested += async (_, _) => await CheckForUpdatesFromSettingsAsync();
        _settingsWindow.UpdateDetailsRequested += (_, _) => ShowPendingUpdate();
        _settingsWindow.ClaudeLoginRequested += (_, _) => StartClaudeLogin(requireClaudeCode: true);
        _settingsWindow.CodexLoginRequested += async (_, _) => await StartCodexLoginAsync();

        _updateWindow.InstallRequested += async (_, _) => await DownloadAndApplyUpdateAsync();
        _updateWindow.CancelRequested += (_, _) =>
        {
            try { _updateCancellation?.Cancel(); }
            catch (ObjectDisposedException) { }
        };

        _onboarding.Completed += (_, _) =>
        {
            ShowWidget();
            ApplyState(_state);
        };
        _onboarding.PrivacyRequested += (_, _) =>
        {
            // Onboarding stays open behind Settings: nothing else brings it back, and the widget
            // is not shown until onboarding completes or closes.
            ShowSettings();
            _settingsWindow.PrivacyNav.IsChecked = true;
        };
        _onboarding.LoginRequested += requireClaudeCode => StartClaudeLogin(requireClaudeCode);
        _onboarding.CodexLoginRequested += async (_, _) => await StartCodexLoginAsync();
        _onboarding.Closed += (_, _) =>
        {
            if (!_settings.FirstRunCompleted) ShowWidget();
        };
    }

    private void ConfigureTray()
    {
        _trayIcon.Text = "dejavu · 사용량 확인 중";
        _trayIcon.Icon = Forms.SystemInformation.SmallIconSize.Width > 16
            ? Drawing.SystemIcons.Application : Drawing.SystemIcons.Information;
        _trayIcon.Visible = _settings.TrayIconStyle != TrayIconStyle.Hidden;

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("사용량 열기", null, (_, _) => _application.Dispatcher.Invoke(ToggleDetails));
        menu.Items.Add("지금 새로고침", null, async (_, _) =>
            await InvokeOnDispatcherAsync(() => RefreshAsync(force: true, bypassClaudeRetry: true)));
        menu.Items.Add("업데이트 확인", null, async (_, _) =>
            await InvokeOnDispatcherAsync(() => CheckForUpdatesAsync(showIfCurrent: true)));
        menu.Items.Add("설정", null, (_, _) => _application.Dispatcher.Invoke(ShowSettings));
        menu.Items.Add(new Forms.ToolStripSeparator());
        // Read the Run key whenever the menu opens: Settings can change it, and a stale check mark would
        // make the next click write the value that is already set. Without CheckOnClick, setting
        // Checked never writes the registry.
        var startup = new Forms.ToolStripMenuItem("Windows 시작 시 실행") { Checked = IsStartupEnabled() };
        startup.Click += (_, _) =>
        {
            SetStartup(!IsStartupEnabled());
            startup.Checked = IsStartupEnabled();
            _application.Dispatcher.BeginInvoke(new Action(() =>
            {
                if (!_disposed) _settingsWindow.RefreshStartupState();
            }));
        };
        menu.Opening += (_, _) => startup.Checked = IsStartupEnabled();
        menu.Items.Add(startup);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => _application.Dispatcher.Invoke(Exit));
        _trayIcon.ContextMenuStrip = menu;
        _trayIcon.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) _application.Dispatcher.Invoke(ToggleDetails);
        };
        _trayIcon.BalloonTipClicked += (_, _) =>
        {
            if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
            _application.Dispatcher.BeginInvoke(new Action(ShowPendingUpdate));
        };
        UpdateTrayIcon();
    }

    private async Task RefreshAsync(bool force = false, bool includeCodex = true, bool bypassClaudeRetry = false)
    {
        if (_disposed) return;
        // Set before the collapse check so an explicit 지금 새로고침 still retries Claude when a newer
        // forced refresh (e.g. the Codex-login follow-up) absorbs it.
        if (bypassClaudeRetry) _claudeRetryBypassRequested = true;
        var forcedGeneration = 0;
        if (force)
        {
            forcedGeneration = ++_forcedRefreshGeneration;
            try { _refreshCancellation?.Cancel(); }
            catch (ObjectDisposedException) { }
        }

        if (!await _refreshGate.WaitAsync(0))
        {
            if (!force) return;
            await _refreshGate.WaitAsync();
            // A newer forced refresh is queued behind this one and reads the same data, so repeated
            // clicks collapse into one refresh (and one Codex app-server) instead of queueing.
            if (forcedGeneration != _forcedRefreshGeneration)
            {
                _refreshGate.Release();
                return;
            }
        }

        CancellationTokenSource? refreshCancellation = null;
        var honorClaudeRetry = true;
        Task<ProviderResult<UsageSnapshot>>? claudeTask = null;
        try
        {
            if (_disposed) return;
            refreshCancellation = new CancellationTokenSource();
            _refreshCancellation = refreshCancellation;
            // Loading keeps each provider's last settled status, so views do not flip to
            // "not connected" while the refresh is in flight.
            ApplyState(ApplicationState.Loading(_state));
            // Only an explicit user refresh (지금 새로고침) tries Claude while a 429's Retry-After is
            // pending; other forced refreshes, such as the Codex-login follow-up, still honor it.
            honorClaudeRetry = !_claudeRetryBypassRequested;
            _claudeRetryBypassRequested = false;
            claudeTask = ReadClaudeAsync(refreshCancellation.Token, honorRetryAt: honorClaudeRetry);
            // A Claude-only refresh carries the last settled Codex status and values.
            var codexTask = includeCodex
                ? ReadCodexAsync(refreshCancellation.Token)
                : Task.FromResult(new ProviderResult<CodexUsageSnapshot>(_state.CodexStatus,
                    CarryCodex(_state.CodexSnapshot), _state.CodexMessage));
            await Task.WhenAll(claudeTask, codexTask);
            if (_disposed || refreshCancellation.IsCancellationRequested) return;
            var claude = await claudeTask;
            var codex = await codexTask;
            // Setting Interval restarts the running timer. Only a full refresh may push the
            // periodic refresh back, or repeated Claude-only refreshes would starve Codex.
            if (includeCodex) ScheduleRefresh(NextRefreshInterval(claude, codex));
            // A Claude-only (login-watch) 429 may outlive the watch: bring the periodic refresh
            // forward to just after RetryAt, never back, so the footer's retry time holds and Codex
            // is not delayed.
            else if (claude.Status == UsageStatus.RateLimited)
                ScheduleRefreshNoLaterThan(CapAtClaudeRetry(
                    TimeSpan.FromMilliseconds(Math.Max(0, _refreshDueTick - Environment.TickCount64)), claude.Status));
            var overall = claude.Status == UsageStatus.Ready || codex.Status == UsageStatus.Ready
                ? UsageStatus.Ready
                : claude.Status == UsageStatus.RateLimited || codex.Status == UsageStatus.RateLimited
                    ? UsageStatus.RateLimited
                    : claude.Status == UsageStatus.Offline || codex.Status == UsageStatus.Offline
                        ? UsageStatus.Offline
                    : claude.Status == UsageStatus.LoginRequired && codex.Status == UsageStatus.LoginRequired
                        ? UsageStatus.LoginRequired : UsageStatus.Error;
            // The combined details header has no room for the per-provider retry hint in narrow
            // themes; the Codex provider line and CodexMessage keep the full message.
            const string retryHint = " · 자동 재시도";
            var codexHeader = codex.Message.EndsWith(retryHint, StringComparison.Ordinal)
                ? codex.Message[..^retryHint.Length] : codex.Message;
            // The Small no-provider widget line has about 220 DIP, so the Claude part stays no longer
            // than the older messages ("Claude 로그인 필요"). ClaudeMessage keeps the full text for
            // the Claude provider line, Settings and Onboarding.
            var claudeHeader = claude.Issue switch
            {
                ClaudeIssue.DesktopHistoryStale => "Claude 기록 대기",
                ClaudeIssue.TokenRefreshPending => "Claude 토큰 대기",
                _ when claude.Message == ClaudeEndpointChangedMessage => "Claude 응답 변경",
                _ when claude.Status == UsageStatus.Ready &&
                       claude.Snapshot?.Source == ClaudeUsageSource.ClaudeDesktop => "Claude Desktop 기록",
                _ => claude.Message
            };
            // A Ready Claude Desktop sample can be up to 40 minutes old, so it is never "up to date".
            var message = claude.Status == UsageStatus.Ready && codex.Status == UsageStatus.Ready &&
                          claude.Snapshot?.Source != ClaudeUsageSource.ClaudeDesktop
                ? "Claude · Codex 사용량이 최신 상태입니다"
                : $"{claudeHeader} · {codexHeader}";
            // A Claude-only refresh did not re-read Codex, so it must not advance the check time
            // shown under visible Codex values. `_state` is the Loading state carrying UpdatedAt.
            var updatedAt = includeCodex || !_settings.ResolveServices(_state).Codex || _state.UpdatedAt is null
                ? DateTimeOffset.Now
                : _state.UpdatedAt;
            ApplyState(new ApplicationState(overall, claude.Snapshot, message, updatedAt,
                RetryAt: claude.Status == UsageStatus.RateLimited ? ClaudeRetryAt : null,
                CodexSnapshot: codex.Snapshot, ClaudeStatus: claude.Status, CodexStatus: codex.Status,
                ClaudeMessage: claude.Message, CodexMessage: codex.Message)
            {
                ClaudeIssue = claude.Issue
            });
        }
        catch (OperationCanceledException) when (refreshCancellation?.IsCancellationRequested == true)
        {
            // A newer forced refresh superseded the current request. If it cancelled an explicit
            // 지금 새로고침 before its Claude read settled, hand the bypass on so that refresh still
            // tries Claude instead of honoring Retry-After. A settled read (for example a fresh 429)
            // already updated the Retry-After state and is not bypassed again.
            if (!honorClaudeRetry && claudeTask is not { IsCompletedSuccessfully: true })
                _claudeRetryBypassRequested = true;
        }
        catch (Exception)
        {
            if (!_disposed)
                ApplyState(_state with { Status = UsageStatus.Error, Message = "사용량을 가져오지 못했어요" });
        }
        finally
        {
            if (ReferenceEquals(_refreshCancellation, refreshCancellation)) _refreshCancellation = null;
            refreshCancellation?.Dispose();
            _refreshGate.Release();
        }
    }

    // A provider that just failed transiently gets two early retries (10 s, then 30 s) before the
    // normal interval, so a failure at logon or right after resume does not stand for a full
    // interval. A streak gets no more early retries until a refresh without a transient failure.
    // Rate limits wait for Retry-After and definitive states (login, missing CLI) never retry early.
    private TimeSpan NextRefreshInterval(ProviderResult<UsageSnapshot> claude, ProviderResult<CodexUsageSnapshot> codex)
    {
        var normal = TimeSpan.FromSeconds(_settings.RefreshSeconds);
        TimeSpan interval;
        if (!claude.Transient && !codex.Transient)
        {
            _transientRetryCount = 0;
            interval = normal;
        }
        else
        {
            interval = _transientRetryCount < TransientRetryDelays.Length
                ? TransientRetryDelays[_transientRetryCount++]
                : normal;
        }
        return CapAtClaudeRetry(interval, claude.Status);
    }

    // The details footer promises the Claude retry at RetryAt, so the next full refresh lands just
    // after it rather than on the first periodic tick past it. The 1 s margin keeps a slightly early
    // tick from being skipped by the Retry-After check; the floor bounds a deadline already past.
    private TimeSpan CapAtClaudeRetry(TimeSpan interval, UsageStatus claudeStatus)
    {
        if (claudeStatus != UsageStatus.RateLimited || _claudeRetryDueTick is not { } due) return interval;
        var untilRetry = TimeSpan.FromMilliseconds(due - Environment.TickCount64) + TimeSpan.FromSeconds(1);
        if (untilRetry < SoonRefreshDelay) untilRetry = SoonRefreshDelay;
        return untilRetry < interval ? untilRetry : interval;
    }

    // The footer's retry time, expressed in the current clock from the monotonic time remaining.
    private DateTimeOffset? ClaudeRetryAt => _claudeRetryDueTick is { } due
        ? DateTimeOffset.Now + TimeSpan.FromMilliseconds(Math.Max(0, due - Environment.TickCount64))
        : null;

    // Assigning Interval restarts the running timer.
    private void ScheduleRefresh(TimeSpan interval)
    {
        _timer.Interval = interval;
        _refreshDueTick = Environment.TickCount64 + (long)interval.TotalMilliseconds;
    }

    // Brings the next periodic refresh forward to `interval`, never back, so a pending 10 s/30 s early
    // retry, resume/unlock/network nudge or Codex refresh keeps its time. The 1 s margin keeps repeated
    // calls for the same deadline from restarting the timer again.
    private void ScheduleRefreshNoLaterThan(TimeSpan interval)
    {
        if ((long)interval.TotalMilliseconds + 1000 < _refreshDueTick - Environment.TickCount64)
            ScheduleRefresh(interval);
    }

    private void ConfigureAutomaticUpdateChecks()
    {
        if (_disposed || !_settings.AutomaticUpdateChecksEnabled || !_updateService.IsInstalled)
        {
            _automaticUpdateTimer.Stop();
            _nextAutomaticUpdateAt = null;
            return;
        }

        // ApplySettings also runs for visual preferences. Preserve an active
        // clock-boundary timer so an unrelated save cannot skip a queued tick.
        if (_automaticUpdateTimer.IsEnabled && _nextAutomaticUpdateAt is not null) return;

        var now = DateTimeOffset.Now;
        var next = HourlyUpdateSchedule.NextCheckAt(now);
        _nextAutomaticUpdateAt = next;
        _automaticUpdateTimer.Interval = next - now;
        _automaticUpdateTimer.Start();
    }

    private async void OnAutomaticUpdateTimerTick(object? sender, EventArgs e)
    {
        _automaticUpdateTimer.Stop();
        try
        {
            await CheckForUpdatesAutomaticallyAsync();
        }
        catch
        {
            // An automatic check is best-effort and must never crash the UI dispatcher.
        }
        finally
        {
            if (!_disposed) ConfigureAutomaticUpdateChecks();
        }
    }

    private async Task CheckForUpdatesAfterStartupAsync()
    {
        await Task.Delay(TimeSpan.FromSeconds(4));
        if (_disposed || !_settings.AutomaticUpdateChecksEnabled) return;
        await CheckForUpdatesAutomaticallyAsync();
    }

    private async Task CheckForUpdatesAutomaticallyAsync()
    {
        // A running download already answered the question and its window must not be reset.
        if (_disposed || !_settings.AutomaticUpdateChecksEnabled || _updateCancellation is not null) return;
        var result = await QueryForUpdatesAsync();
        if (_disposed || !_settings.AutomaticUpdateChecksEnabled ||
            result.Status != UpdateCheckStatus.Available ||
            !AutomaticUpdatePolicy.ShouldNotify(result.Version, _settings.LastNotifiedUpdateVersion)) return;
        NotifyUpdateAvailable(result.Version!);
    }

    private async Task CheckForUpdatesAsync(bool showIfCurrent)
    {
        if (_disposed) return;
        var result = await QueryForUpdatesAsync();
        if (_disposed) return;
        switch (result.Status)
        {
            case UpdateCheckStatus.Available:
                ShowPendingUpdate();
                break;
            case UpdateCheckStatus.Current when showIfCurrent:
                _updateWindow.ShowCurrent(_settings.AutomaticUpdateChecksEnabled
                    ? null
                    : "자동 업데이트 확인이 꺼져 있어요. 새 버전 알림을 받으려면 설정에서 자동 업데이트 확인을 켜 주세요.");
                break;
            case UpdateCheckStatus.NotInstalled when showIfCurrent:
                _updateWindow.ShowStatus("설치 버전에서 확인할 수 있어요",
                    "자동 업데이트는 Velopack 설치 버전부터 사용할 수 있습니다. 현재 개발용 실행 파일은 업데이트 대상이 아닙니다.");
                break;
            case UpdateCheckStatus.Error when showIfCurrent:
                _updateWindow.ShowStatus("업데이트를 확인하지 못했어요",
                    "업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.");
                break;
        }
    }

    private async Task CheckForUpdatesFromSettingsAsync()
    {
        if (_disposed) return;
        var result = await QueryForUpdatesAsync();
        if (_disposed) return;
        switch (result.Status)
        {
            case UpdateCheckStatus.Available:
                _settingsWindow.SetUpdateCheckResult($"{result.Version} 업데이트를 사용할 수 있습니다.", updateAvailable: true);
                break;
            case UpdateCheckStatus.Current:
                _settingsWindow.SetUpdateCheckResult("현재 최신 버전을 사용하고 있습니다.");
                break;
            case UpdateCheckStatus.NotInstalled:
                _settingsWindow.SetUpdateCheckResult("설치 버전에서만 업데이트를 확인할 수 있습니다.");
                break;
            default:
                _settingsWindow.SetUpdateCheckResult("업데이트 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.");
                break;
        }
    }

    private async Task<UpdateCheckResult> QueryForUpdatesAsync()
    {
        // While a download runs, report the update being downloaded without querying: a new result
        // could only replace or clear it. The Available paths then just bring its window forward.
        if (_updateCancellation is not null && _pendingUpdate is { } downloading)
            return new UpdateCheckResult(UpdateCheckStatus.Available, downloading.TargetFullRelease.Version.ToString());
        var updateCheck = _updateCheckTask;
        if (updateCheck is null)
        {
            updateCheck = QueryForUpdatesCoreAsync();
            _updateCheckTask = updateCheck;
        }

        try
        {
            return await updateCheck;
        }
        finally
        {
            if (ReferenceEquals(_updateCheckTask, updateCheck)) _updateCheckTask = null;
        }
    }

    private async Task<UpdateCheckResult> QueryForUpdatesCoreAsync()
    {
        try
        {
            if (!_updateService.IsInstalled)
            {
                _pendingUpdate = null;
                return new UpdateCheckResult(UpdateCheckStatus.NotInstalled);
            }
            // A timeout is an Error; the abandoned Velopack task finishes in the background and its
            // result is discarded, so it can never overwrite a later check.
            var update = await _updateService.CheckAsync().WaitAsync(UpdateCheckTimeout);
            if (update is null)
            {
                _pendingUpdate = null;
                return new UpdateCheckResult(UpdateCheckStatus.Current);
            }
            _pendingUpdate = update;
            return new UpdateCheckResult(UpdateCheckStatus.Available,
                update.TargetFullRelease.Version.ToString());
        }
        catch
        {
            // A transient failure (offline, DNS, GitHub rate limit, timeout) proves nothing about the
            // release: keep an update that was already offered so its buttons keep working.
            return new UpdateCheckResult(UpdateCheckStatus.Error);
        }
    }

    private void ShowPendingUpdate()
    {
        if (_pendingUpdate is null)
        {
            // The offer was withdrawn by a definitive check: ask again and show the answer instead
            // of ignoring the notification click or Settings button.
            _ = CheckForUpdatesAsync(showIfCurrent: true);
            return;
        }
        var version = _pendingUpdate.TargetFullRelease.Version.ToString();
        RememberNotifiedUpdateVersion(version);
        _updateWindow.ShowAvailable(version,
            _pendingUpdate.TargetFullRelease.NotesMarkdown);
    }

    private void NotifyUpdateAvailable(string version)
    {
        if (_pendingUpdate is null) return;
        RememberNotifiedUpdateVersion(version);
        if (_settings.TrayIconStyle == TrayIconStyle.Hidden || !_trayIcon.Visible)
        {
            ShowPendingUpdate();
            return;
        }

        try
        {
            _trayIcon.ShowBalloonTip(10_000, $"dejavu {version} 업데이트",
                "새 버전을 사용할 수 있습니다. 눌러 변경 내용과 업데이트 옵션을 확인하세요.",
                Forms.ToolTipIcon.Info);
        }
        catch
        {
            ShowPendingUpdate();
        }
    }

    private void RememberNotifiedUpdateVersion(string version)
    {
        if (string.Equals(_settings.LastNotifiedUpdateVersion, version,
                StringComparison.OrdinalIgnoreCase)) return;
        _settings.LastNotifiedUpdateVersion = version;
        _settings.Save();
    }

    private async Task DownloadAndApplyUpdateAsync()
    {
        if (_updateCancellation is not null) return;
        // Capture the offer once: nothing may swap or clear the release between download and apply.
        var update = _pendingUpdate;
        if (update is null)
        {
            await CheckForUpdatesAsync(showIfCurrent: true);
            return;
        }
        var updateCancellation = new CancellationTokenSource();
        _updateCancellation = updateCancellation;
        // Every progress report re-arms the stall watchdog; a connection that dies silently mid-body
        // would otherwise leave the window on the same percentage forever.
        using var stall = new CancellationTokenSource(UpdateDownloadStallTimeout);
        using var download = CancellationTokenSource.CreateLinkedTokenSource(updateCancellation.Token, stall.Token);
        try
        {
            _updateWindow.SetDownloading(0);
            await _updateService.DownloadAsync(update,
                progress =>
                {
                    try { stall.CancelAfter(UpdateDownloadStallTimeout); }
                    catch (ObjectDisposedException) { }
                    if (_disposed || updateCancellation.IsCancellationRequested) return;
                    _application.Dispatcher.BeginInvoke(() =>
                    {
                        if (!_disposed && !updateCancellation.IsCancellationRequested)
                            _updateWindow.SetDownloading(progress);
                    });
                },
                download.Token);
            if (_disposed) return;
            // A user cancel that arrived after the last byte still cancels. A watchdog that fired
            // after the download finished does not discard it.
            if (updateCancellation.IsCancellationRequested)
            {
                _updateWindow.SetError("업데이트가 취소되었습니다.");
                return;
            }
            _updateWindow.SetDownloading(100);
            // The updater waits for this process to exit, so Exit() runs the normal shutdown (tray
            // icon removal, single-instance mutex release) before the update is applied.
            _updateService.ApplyAfterExitAndRestart(update);
            Exit();
        }
        catch (Exception) when (_disposed)
        {
            // Shutdown cancelled the download.
        }
        catch (Exception) when (updateCancellation.IsCancellationRequested)
        {
            _updateWindow.SetError("업데이트가 취소되었습니다.");
        }
        catch (Exception) when (stall.IsCancellationRequested)
        {
            _updateWindow.SetError("다운로드가 멈춰 중단했습니다. 잠시 후 다시 시도해 주세요.");
        }
        catch (Exception)
        {
            _updateWindow.SetError("업데이트를 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.");
        }
        finally
        {
            if (ReferenceEquals(_updateCancellation, updateCancellation)) _updateCancellation = null;
            updateCancellation.Dispose();
        }
    }

    // Every failure keeps the last Claude values through CarryClaude; `_state` is the Loading state,
    // which carries the last settled Claude status, message and snapshot.
    private async Task<ProviderResult<UsageSnapshot>> ReadClaudeAsync(CancellationToken cancellationToken,
        bool honorRetryAt)
    {
        // Calling a rate-limited endpoint early can extend the limit. A changed credential file (a new
        // login or token refresh) allows one real request; the check never reads the file's contents.
        if (honorRetryAt && _claudeRetryDueTick is { } due && Environment.TickCount64 < due &&
            ClaudeCredentialFingerprint() == _claudeRetryCredential)
            return new ProviderResult<UsageSnapshot>(UsageStatus.RateLimited, CarryClaude(_state.Snapshot),
                ClaudeRateLimitedMessage);
        try
        {
            var snapshot = await _claudeClient.GetUsageAsync(cancellationToken);
            _claudeRetryDueTick = null;
            // Desktop history names its capture time, so an older sample never reads as a new one.
            var message = snapshot.Source != ClaudeUsageSource.ClaudeDesktop ? "Claude 최신"
                : snapshot.CapturedAt is { } capturedAt ? $"Claude Desktop 기록 {capturedAt.LocalDateTime:HH:mm}"
                : "Claude Desktop 기록";
            return new ProviderResult<UsageSnapshot>(UsageStatus.Ready, snapshot, message);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (ClaudeTokenExpiredException)
        {
            // Not a login problem: running Claude Code renews the token and the next refresh reads it.
            _claudeRetryDueTick = null;
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, CarryClaude(_state.Snapshot),
                "Claude 토큰 갱신 대기", Issue: ClaudeIssue.TokenRefreshPending);
        }
        catch (ClaudeDesktopHistoryStaleException)
        {
            // Desktop closed or idle; its next sample is picked up by the periodic refresh.
            _claudeRetryDueTick = null;
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, CarryClaude(_state.Snapshot),
                "Claude Desktop 기록 대기", Issue: ClaudeIssue.DesktopHistoryStale);
        }
        catch (ClaudeLoginRequiredException)
        {
            _claudeRetryDueTick = null;
            return new ProviderResult<UsageSnapshot>(UsageStatus.LoginRequired, CarryClaude(_state.Snapshot),
                "Claude 로그인 필요");
        }
        catch (ClaudeRateLimitException exception)
        {
            var delay = exception.RetryAfter < MinimumClaudeRetryDelay ? MinimumClaudeRetryDelay
                : exception.RetryAfter > MaximumClaudeRetryDelay ? MaximumClaudeRetryDelay
                : exception.RetryAfter;
            _claudeRetryDueTick = Environment.TickCount64 + (long)delay.TotalMilliseconds;
            _claudeRetryCredential = ClaudeCredentialFingerprint();
            return new ProviderResult<UsageSnapshot>(UsageStatus.RateLimited, CarryClaude(_state.Snapshot),
                ClaudeRateLimitedMessage);
        }
        catch (HttpRequestException exception) when (exception.StatusCode is null)
        {
            // DNS, connect or TLS failure: the network really is unavailable.
            return new ProviderResult<UsageSnapshot>(UsageStatus.Offline, CarryClaude(_state.Snapshot),
                "Claude 오프라인", Transient: true);
        }
        catch (HttpRequestException exception) when ((int)exception.StatusCode!.Value >= 500)
        {
            // 5xx or 529 overloaded: Anthropic is reachable but failing.
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, CarryClaude(_state.Snapshot),
                "Claude 서버 오류", Transient: true);
        }
        catch (HttpRequestException)
        {
            // Any other 4xx: the undocumented usage endpoint changed; retrying early cannot help.
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, CarryClaude(_state.Snapshot),
                ClaudeEndpointChangedMessage);
        }
        catch (OperationCanceledException)
        {
            // The 12 s HttpClient timeout: the refresh token was not cancelled (see the rethrow above).
            return new ProviderResult<UsageSnapshot>(UsageStatus.Offline, CarryClaude(_state.Snapshot),
                "Claude 응답 지연", Transient: true);
        }
        catch
        {
            // For example a partial credential read while Claude Code rewrites the file.
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, CarryClaude(_state.Snapshot),
                "Claude 확인 실패", Transient: true);
        }
    }

    private static (DateTime WriteUtc, long Length)? ClaudeCredentialFingerprint()
    {
        try
        {
            var path = ClaudeEnvironmentDetector.FindCredentialPath();
            if (path is null) return null;
            var file = new FileInfo(path);
            return (file.LastWriteTimeUtc, file.Length);
        }
        catch
        {
            return null;
        }
    }

    // A failed read keeps the last values, but never a limit whose window has already reset, nor
    // Claude Desktop history older than the reader's own recency window: those show --%. The snapshot
    // object stays, so automatic detection keeps the provider slot and the widget keeps its size.
    private static UsageSnapshot? CarryClaude(UsageSnapshot? previous)
    {
        if (previous is null) return null;
        var now = DateTimeOffset.Now;
        if (previous.Source == ClaudeUsageSource.ClaudeDesktop)
        {
            return previous.CapturedAt is { } capturedAt && now - capturedAt <= ClaudeDesktopUsageReader.MaximumSampleAge
                ? previous
                : previous with { FiveHour = null, Weekly = null, Fable = null };
        }

        var fiveHour = Live(previous.FiveHour, now);
        var weekly = Live(previous.Weekly, now);
        var fable = Live(previous.Fable, now);
        if (ReferenceEquals(fiveHour, previous.FiveHour) && ReferenceEquals(weekly, previous.Weekly) &&
            ReferenceEquals(fable, previous.Fable)) return previous;
        return previous with
        {
            FiveHour = fiveHour,
            Weekly = weekly,
            Fable = fable,
            FableExpired = previous.FableExpired || previous.Fable is not null && fable is null
        };
    }

    private static CodexUsageSnapshot? CarryCodex(CodexUsageSnapshot? previous)
    {
        if (previous is null) return null;
        var now = DateTimeOffset.Now;
        var fiveHour = Live(previous.FiveHour, now);
        var weekly = Live(previous.Weekly, now);
        return ReferenceEquals(fiveHour, previous.FiveHour) && ReferenceEquals(weekly, previous.Weekly)
            ? previous
            : previous with
            {
                FiveHour = fiveHour,
                Weekly = weekly,
                WeeklyExpired = previous.WeeklyExpired || previous.Weekly is not null && weekly is null
            };
    }

    private static UsageLimit? Live(UsageLimit? limit, DateTimeOffset now) =>
        limit?.ResetsAt is { } resetsAt && resetsAt <= now ? null : limit;

    private async Task<ProviderResult<CodexUsageSnapshot>> ReadCodexAsync(CancellationToken cancellationToken)
    {
        try
        {
            var snapshot = await _codexClient.GetUsageAsync(cancellationToken);
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.Ready, snapshot, "Codex 최신");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (CodexLoginRequiredException exception)
        {
            _codexLoginRequiredAccountMissing = exception.AccountMissing;
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.LoginRequired, CarryCodex(_state.CodexSnapshot),
                "Codex 로그인 필요");
        }
        catch (CodexBackendFailedException)
        {
            // Upstream returns -32603 only after it found ChatGPT auth, so a LoginRequired that came
            // from a missing account is stale. A 401-based LoginRequired stays sticky.
            return _state.CodexStatus == UsageStatus.LoginRequired && _codexLoginRequiredAccountMissing
                ? new(UsageStatus.Error, CarryCodex(_state.CodexSnapshot), "Codex 확인 실패 · 자동 재시도", Transient: true)
                : TransientCodexResult(UsageStatus.Error, "Codex 확인 실패 · 자동 재시도");
        }
        catch (CodexCliUnavailableException)
        {
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.Error, CarryCodex(_state.CodexSnapshot), "Codex CLI 필요");
        }
        catch (CodexTimeoutException)
        {
            return TransientCodexResult(UsageStatus.Offline, "Codex 응답 지연 · 자동 재시도");
        }
        catch
        {
            // CodexReadFailedException (a transient JSON-RPC error, early exit or malformed reply),
            // a start or pipe failure: not a login problem, so the next refresh simply retries.
            return TransientCodexResult(UsageStatus.Error, "Codex 확인 실패 · 자동 재시도");
        }
    }

    // A transient failure proves nothing about login: keep a settled LoginRequired until a Ready
    // read, or a backend failure that contradicts a missing account (see ReadCodexAsync).
    // `_state` is the Loading state, which carries the last settled Codex status.
    private ProviderResult<CodexUsageSnapshot> TransientCodexResult(UsageStatus status, string message) =>
        _state.CodexStatus == UsageStatus.LoginRequired
            ? new(UsageStatus.LoginRequired, CarryCodex(_state.CodexSnapshot), "Codex 로그인 필요")
            : new(status, CarryCodex(_state.CodexSnapshot), message, Transient: true);

    private void ApplyState(ApplicationState state)
    {
        if (_disposed) return;
        _state = state;
        // The login watch starts only from a user login action (StartClaudeLogin); the periodic
        // timer still picks up a login made outside Dejavu.
        if (state.ClaudeStatus == UsageStatus.Ready &&
            (!_loginWatchTimer.IsEnabled || !_loginWatchRequiresClaudeCode ||
             state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode))
            _loginWatchTimer.Stop();
        _widget.UpdateState(state);
        _details.UpdateState(state, _settings);
        _settingsWindow.UpdateClaudeConnectionState(state);
        _onboarding.UpdateState(state);
        UpdateTrayIcon();
        WriteDiagnostics(state);
    }

    private void WriteDiagnostics(ApplicationState state) =>
        AppDiagnostics.Write(state, _widget, _settings.WidgetOpacity, _settings.WidgetPlacement,
            _taskbarTracker.State, _taskbarTracker.RediscoveryCount);

    private void ApplySettings()
    {
        if (_disposed) return;
        ThemeManager.Apply(_settings);
        _widget.ApplySettings(_settings);
        _updateWindow.ApplyTheme(_settings.WidgetTheme);
        _onboarding.ApplyTheme(_settings.WidgetTheme);
        // Placement changes, Reset position and Restore defaults all arrive here; leaving
        // InTaskbar disables the tracker and clears the dock before the widget is positioned.
        SyncTaskbarTracking();
        if (_settings.WidgetPlacement != WidgetPlacement.Custom) _widget.PositionFromSettings(forceDefault: true);
        else
        {
            _widget.KeepCurrentPositionVisible();
            _settings.Save();
        }
        _details.UpdateState(_state, _settings);
        // A save may bring the next refresh forward (a shorter interval, or the Claude RetryAt cap) but
        // never pushes back a pending early retry, resume/unlock/network nudge or periodic tick. A longer
        // interval takes effect from the next full refresh.
        ScheduleRefreshNoLaterThan(CapAtClaudeRetry(TimeSpan.FromSeconds(_settings.RefreshSeconds), _state.ClaudeStatus));
        ConfigureAutomaticUpdateChecks();
        UpdateTrayIcon();
        WriteDiagnostics(_state);
    }

    private void ShowWidget()
    {
        if (_disposed) return;
        _widgetRequested = true;
        // SyncTaskbarTracking always finishes with UpdateWidgetVisibility.
        SyncTaskbarTracking();
    }

    private bool TaskbarTrackingRequested =>
        !_disposed && _widgetRequested && _settings.WidgetPlacement == WidgetPlacement.InTaskbar;

    private void SyncTaskbarTracking()
    {
        // SetEnabled is idempotent and never raises StateChanged synchronously, so the
        // current state is applied here directly (Suppressed "settling" right after enabling).
        _taskbarTracker.SetEnabled(TaskbarTrackingRequested);
        ApplyTaskbarState(_taskbarTracker.State);
    }

    private void OnTaskbarStateChanged(object? sender, TaskbarTrackerState state)
    {
        if (_disposed) return;
        ApplyTaskbarState(state);
        WriteDiagnostics(_state);
    }

    private void ApplyTaskbarState(TaskbarTrackerState state)
    {
        if (_disposed) return;
        switch (state.Status)
        {
            case TaskbarDockStatus.Docked:
                // The widget ignores an unchanged dock, so repeated settings saves stay cheap.
                _widget.SetTaskbarDock(state.Dock);
                _taskbarSuppressed = false;
                break;
            case TaskbarDockStatus.Suppressed:
                // Keep the last dock so the widget returns to the same slot afterwards.
                _taskbarSuppressed = true;
                break;
            default:
                // Fallback shows the ordinary floating widget; Inactive means another placement.
                _widget.SetTaskbarDock(null);
                _taskbarSuppressed = false;
                break;
        }
        UpdateWidgetVisibility();
        _settingsWindow.UpdateTaskbarStatus(state);
    }

    private void UpdateWidgetVisibility()
    {
        if (_disposed || !_widgetRequested || _widgetClosed) return;
        if (_taskbarSuppressed)
        {
            // Really hide while a fullscreen app owns the monitor or the taskbar is settling.
            // Positioning afterwards keeps a valid anchor for the details window.
            if (_widget.IsVisible) _widget.Hide();
            _widget.PositionFromSettings();
            return;
        }

        // A shown Custom widget keeps its displayed top-left point; ApplySettings clamps and saves it.
        if (_settings.WidgetPlacement != WidgetPlacement.Custom || !_widget.IsVisible)
            _widget.PositionFromSettings();
        if (!_widget.IsVisible) _widget.Show();
        _widget.RequestTopmostRepair("show_widget");
        if (_widget.IsTaskbarDocked)
            _widget.RaiseAboveTaskbarIfCovered(_taskbarTracker.TaskbarHandle, "docked");
    }

    private void ToggleDetails()
    {
        if (_disposed) return;
        if (_details.IsVisible) _details.Hide();
        // The press of this widget or tray click already closed the popup through deactivation.
        else if (_details.WasJustDismissed) return;
        else
        {
            _details.UpdateState(_state, _settings);
            _details.ShowNear(_widget);
        }
    }

    private void ShowSettings()
    {
        if (_disposed) return;
        _details.Hide();
        _settingsWindow.ShowAndActivate();
    }

    internal void ShowSettingsFromExternalActivation()
    {
        if (!_disposed) ShowSettings();
    }

    private void StartClaudeLogin(bool requireClaudeCode)
    {
        if (_disposed) return;
        try
        {
            _loginWatchRequiresClaudeCode = requireClaudeCode;
            var environment = ClaudeEnvironmentDetector.Detect();
            if (environment.IsInstalled) ClaudeEnvironmentDetector.OpenLogin();
            else if (!requireClaudeCode && ClaudeDesktopUsageReader.IsInstalled) ClaudeDesktopUsageReader.OpenDesktop();
            else ClaudeEnvironmentDetector.OpenSetupPage();
            _loginWatchUntil = DateTimeOffset.Now + LoginWatchDuration;
            _loginWatchTimer.Start();
            _onboarding.RefreshDetection();
        }
        catch
        {
            ApplyState(_state with
            {
                // A failed launch says nothing new about the login, usage, token, Desktop history or
                // rate limit: keep the settled status and ClaudeIssue. Only a never-checked Claude
                // becomes Error. The message reaches the details provider line.
                ClaudeStatus = _state.ClaudeStatus == UsageStatus.Loading ? UsageStatus.Error : _state.ClaudeStatus,
                ClaudeMessage = "Claude 로그인 창을 열지 못했습니다"
            });
            // The issue, login and Ready cards render fixed text, so report the failure on the cards
            // after ApplyState redrew them; the next state update replaces it.
            _settingsWindow.ShowClaudeLoginLaunchFailed();
            _onboarding.ShowClaudeLoginLaunchFailed();
        }
    }

    private async Task StartCodexLoginAsync()
    {
        if (_codexLoginInProgress)
        {
            // A repeated click while the browser login is pending reopens its page instead of doing
            // nothing until the 5-minute timeout. The same app-server keeps waiting for the callback,
            // so no second login child or callback port is involved.
            if (_codexLoginAuthUrl is { } authUrl)
            {
                try { Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true }); }
                catch { }
            }
            return;
        }
        if (CodexUsageClient.FindExecutable() is null)
        {
            try { CodexUsageClient.OpenSetupPage(); }
            catch
            {
                ApplyState(_state with
                {
                    CodexStatus = UsageStatus.Error,
                    CodexMessage = "Codex 설치 안내를 열지 못했습니다"
                });
            }
            return;
        }

        _codexLoginInProgress = true;
        var codexLoginCancellation = new CancellationTokenSource();
        _codexLoginCancellation = codexLoginCancellation;
        _onboarding.SetCodexLoginPending(true);
        _settingsWindow.SetCodexLoginPending(true);
        try
        {
            await _codexClient.LoginAsync(codexLoginCancellation.Token, url => _codexLoginAuthUrl = url);
            if (_disposed || codexLoginCancellation.IsCancellationRequested) return;
            // The login app-server and its callback have exited, so the auth URL is spent: a click
            // during the follow-up refresh must not reopen it. `_codexLoginInProgress` stays set
            // until `finally`, so such a click does nothing instead of starting a second login.
            _codexLoginAuthUrl = null;
            _onboarding.SetCodexLoginPending(false);
            _settingsWindow.SetCodexLoginPending(false);
            // A completed login makes a settled LoginRequired, or a failure before any successful read
            // that offered login as a fallback, stale: show the checking state (login button collapsed)
            // and let the follow-up read decide, so a transient failure there does not bring the login
            // prompt back.
            if (_state.CodexStatus == UsageStatus.LoginRequired ||
                _state.CodexStatus != UsageStatus.Ready && _state.CodexSnapshot is null)
                ApplyState(_state with { CodexStatus = UsageStatus.Loading, CodexMessage = "Codex 확인 중" });
            await RefreshAsync(force: true);
        }
        catch (CodexCliUnavailableException)
        {
            try { CodexUsageClient.OpenSetupPage(); }
            catch
            {
                if (!_disposed)
                {
                    ApplyState(_state with
                    {
                        CodexStatus = UsageStatus.Error,
                        CodexMessage = "Codex 설치 안내를 열지 못했습니다"
                    });
                }
            }
        }
        catch (OperationCanceledException) when (codexLoginCancellation.IsCancellationRequested)
        {
            // Application shutdown cancels the pending browser login.
        }
        catch (CodexLoginFailedException)
        {
            ApplyCodexLoginFailure("Codex 로그인을 완료하지 못했습니다");
        }
        catch
        {
            ApplyCodexLoginFailure("Codex 로그인 창을 열지 못했습니다");
        }
        finally
        {
            _codexLoginInProgress = false;
            _codexLoginAuthUrl = null;
            if (ReferenceEquals(_codexLoginCancellation, codexLoginCancellation)) _codexLoginCancellation = null;
            codexLoginCancellation.Dispose();
            if (!_disposed)
            {
                _onboarding.SetCodexLoginPending(false);
                _settingsWindow.SetCodexLoginPending(false);
            }
        }
    }

    // A failed, abandoned or timed-out login says nothing new about the stored account. The login
    // button is never offered while Codex is Ready, so Ready here means a read succeeded while the
    // login was pending and is kept. Otherwise a logged-out account keeps the login prompt, and any
    // other status becomes a transient Error instead of seeding the sticky LoginRequired rule.
    private void ApplyCodexLoginFailure(string message)
    {
        if (_disposed || _state.CodexStatus == UsageStatus.Ready) return;
        ApplyState(_state with
        {
            CodexStatus = _state.CodexStatus == UsageStatus.LoginRequired ? UsageStatus.LoginRequired : UsageStatus.Error,
            CodexMessage = message
        });
    }

    private void UpdateTrayIcon()
    {
        if (_settings.TrayIconStyle == TrayIconStyle.Hidden)
        {
            _trayIcon.Visible = false;
            return;
        }

        var (showClaude, showCodex) = _settings.ResolveServices(_state);
        var selected = !showClaude && showCodex
            ? _state.CodexSnapshot?.DisplayLimit
            : _settings.PrimaryMetric switch
        {
            PrimaryMetric.Weekly => _state.Snapshot?.Weekly,
            PrimaryMetric.Fable => _state.Snapshot?.Fable,
            PrimaryMetric.Codex => _state.CodexSnapshot?.DisplayLimit,
            _ => _state.Snapshot?.FiveHour
        };
        var icon = _settings.TrayIconStyle == TrayIconStyle.Percentage
            ? CreatePercentageIcon(selected?.Percent)
            : CreateMarkIcon();
        _trayIcon.Icon = icon;
        _trayIcon.Visible = true;
        _generatedIcon?.Dispose();
        _generatedIcon = icon;
        var providers = new List<string>();
        if (showClaude) providers.Add($"Claude {Format(_state.Snapshot?.Weekly)}");
        if (showCodex) providers.Add($"Codex {Format(_state.CodexSnapshot?.DisplayLimit)}");
        _trayIcon.Text = Truncate(providers.Count == 0 ? "dejavu · 연결된 서비스 없음"
            : $"dejavu · {string.Join(" · ", providers)}", 63);
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
        => QueueWidgetTopmostRepair("display_settings_changed", reposition: true);

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume) return;
        QueueWidgetTopmostRepair("power_resume", notifyTaskbar: true);
        QueueAutomaticUpdateScheduleRecovery(checkIfOverdue: true);
        // Values from before the sleep must not wait out the rest of a full interval.
        QueueSoonRefresh();
    }

    private void OnSystemTimeChanged(object? sender, EventArgs e) =>
        QueueAutomaticUpdateScheduleRecovery(checkIfOverdue: true);

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.SessionLogon
            or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)
        {
            QueueWidgetTopmostRepair($"session_{e.Reason}", notifyTaskbar: true);
            QueueSoonRefresh();
        }
    }

    // Raised on a thread-pool thread. Only a provider that is currently failing can gain from it.
    private void OnNetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs e)
    {
        if (e.IsAvailable) QueueSoonRefresh(onlyAfterFailure: true);
    }

    // Moves the next periodic refresh a few seconds ahead instead of refreshing directly, so it
    // coalesces with a refresh in flight and never cancels a pending Codex read.
    private void QueueSoonRefresh(bool onlyAfterFailure = false)
    {
        if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
        _application.Dispatcher.BeginInvoke(new Action(() =>
        {
            if (_disposed) return;
            if (onlyAfterFailure &&
                _state.ClaudeStatus is not (UsageStatus.Offline or UsageStatus.Error) &&
                _state.CodexStatus is not (UsageStatus.Offline or UsageStatus.Error)) return;
            _transientRetryCount = 0;
            ScheduleRefresh(SoonRefreshDelay);
        }));
    }

    private void QueueWidgetTopmostRepair(string reason, bool reposition = false, bool notifyTaskbar = false)
    {
        if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
        _application.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
        {
            if (_disposed) return;
            if (notifyTaskbar && TaskbarTrackingRequested)
            {
                // Explorer may rebuild or move the taskbar while the session was away.
                // The tracker re-settles without raising StateChanged synchronously.
                _taskbarTracker.NotifyShellChanged(reason);
                ApplyTaskbarState(_taskbarTracker.State);
            }
            if (reposition) _widget.PositionFromSettings();
            _widget.RequestTopmostRepair(reason);
        }));
    }

    private void QueueAutomaticUpdateScheduleRecovery(bool checkIfOverdue)
    {
        if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
        _ = InvokeOnDispatcherAsync(async () =>
        {
            if (_disposed) return;
            var overdue = checkIfOverdue && _nextAutomaticUpdateAt is DateTimeOffset next &&
                          DateTimeOffset.Now >= next;
            _automaticUpdateTimer.Stop();
            if (overdue && _settings.AutomaticUpdateChecksEnabled && _updateService.IsInstalled)
                await CheckForUpdatesAutomaticallyAsync();
            if (!_disposed) ConfigureAutomaticUpdateChecks();
        });
    }

    private async Task InvokeOnDispatcherAsync(Func<Task> action)
    {
        if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
        try
        {
            if (_application.Dispatcher.CheckAccess()) await action();
            else await _application.Dispatcher.InvokeAsync(action).Task.Unwrap();
        }
        catch (TaskCanceledException) when (_disposed || _application.Dispatcher.HasShutdownStarted) { }
        catch (InvalidOperationException) when (_disposed || _application.Dispatcher.HasShutdownStarted) { }
    }

    private void Exit()
    {
        Dispose();
        _application.Shutdown();
    }

    private static bool IsStartupEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(RunValueName) is string;
        }
        catch { return false; }
    }

    private static void SetStartup(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (enabled)
            {
                var executable = Environment.ProcessPath ?? throw new InvalidOperationException("Executable path is unavailable.");
                key.SetValue(RunValueName, $"\"{executable}\"");
                key.DeleteValue("UsageBarForClaude", false);
                key.DeleteValue("ClaudeUsageTray", false);
            }
            else
            {
                key.DeleteValue(RunValueName, false);
                key.DeleteValue("UsageBarForClaude", false);
                key.DeleteValue("ClaudeUsageTray", false);
            }
        }
        catch { }
    }

    internal static void RemoveStartupRegistration()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(RunValueName, false);
            key?.DeleteValue("UsageBarForClaude", false);
            key?.DeleteValue("ClaudeUsageTray", false);
        }
        catch
        {
            // Uninstall must continue even when the Run key is unavailable.
        }
    }

    internal static void PerformUninstallCleanup()
    {
        RemoveStartupRegistration();
        DeleteUserDataDirectory("dejavu");
        DeleteUserDataDirectory("ClaudeUsageTray");
    }

    private static void DeleteUserDataDirectory(string directoryName)
    {
        try
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData)) return;

            var root = Path.GetFullPath(localAppData).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                       + Path.DirectorySeparatorChar;
            var target = Path.GetFullPath(Path.Combine(root, directoryName));
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return;

            if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
        }
        catch
        {
            // User-data cleanup must not prevent Velopack from removing the application.
        }
    }

    private static void MigrateExistingStartupRegistration()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            var hasExistingRegistration = key.GetValue(RunValueName) is string ||
                                          key.GetValue("UsageBarForClaude") is string ||
                                          key.GetValue("ClaudeUsageTray") is string;
            if (!hasExistingRegistration) return;

            var executable = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(executable)) return;
            var executableDirectory = Path.GetDirectoryName(executable);
            if (string.Equals(Path.GetFileName(executableDirectory), "current", StringComparison.OrdinalIgnoreCase))
            {
                var rootDirectory = Directory.GetParent(executableDirectory!)?.FullName;
                if (!string.IsNullOrWhiteSpace(rootDirectory))
                    executable = Path.Combine(rootDirectory, Path.GetFileName(executable));
            }
            key.SetValue(RunValueName, $"\"{executable}\"");
            key.DeleteValue("UsageBarForClaude", false);
            key.DeleteValue("ClaudeUsageTray", false);
        }
        catch
        {
            // A registry migration must never prevent the widget from starting.
        }
    }

    private static string Format(UsageLimit? value) => value is null ? "--%" : $"{value.Percent:0}%";
    private static string Truncate(string value, int maximum) => value.Length <= maximum ? value : value[..maximum];

    private static Drawing.Icon CreateMarkIcon()
    {
        using var bitmap = new Drawing.Bitmap(32, 32);
        using var graphics = Drawing.Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Drawing.Color.Transparent);
        using var background = new Drawing.SolidBrush(Drawing.Color.FromArgb(109, 142, 255));
        graphics.FillEllipse(background, 2, 2, 28, 28);
        using var pen = new Drawing.Pen(Drawing.Color.White, 2.2f);
        graphics.DrawArc(pen, 8, 8, 16, 16, -80, 285);
        graphics.DrawLine(pen, 16, 16, 22, 11);
        return CloneIcon(bitmap);
    }

    private static Drawing.Icon CreatePercentageIcon(double? percent)
    {
        using var bitmap = new Drawing.Bitmap(32, 32);
        using var graphics = Drawing.Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Drawing.Color.Transparent);
        var value = Math.Clamp(percent ?? 0, 0, 100);
        var color = percent is null ? Drawing.Color.Gray : value >= 90 ? Drawing.Color.FromArgb(240, 113, 120)
            : value >= 70 ? Drawing.Color.FromArgb(230, 167, 86) : Drawing.Color.FromArgb(109, 142, 255);
        using var background = new Drawing.SolidBrush(Drawing.Color.FromArgb(24, 24, 27));
        using var border = new Drawing.Pen(color, 2.5f);
        graphics.FillEllipse(background, 2, 2, 28, 28);
        graphics.DrawArc(border, 3, 3, 26, 26, -90, (float)(360 * value / 100));
        var text = percent is null ? "--" : Math.Round(value).ToString("0");
        using var font = new Drawing.Font("Segoe UI", text.Length >= 3 ? 8f : 10f, Drawing.FontStyle.Bold, Drawing.GraphicsUnit.Pixel);
        Forms.TextRenderer.DrawText(graphics, text, font, new Drawing.Rectangle(4, 7, 24, 18), Drawing.Color.White,
            Forms.TextFormatFlags.HorizontalCenter | Forms.TextFormatFlags.VerticalCenter | Forms.TextFormatFlags.NoPadding);
        return CloneIcon(bitmap);
    }

    private static Drawing.Icon CloneIcon(Drawing.Bitmap bitmap)
    {
        var handle = bitmap.GetHicon();
        try { return (Drawing.Icon)Drawing.Icon.FromHandle(handle).Clone(); }
        finally { DestroyIcon(handle); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.TimeChanged -= OnSystemTimeChanged;
        if (_networkChangeSubscribed)
        {
            try { NetworkChange.NetworkAvailabilityChanged -= OnNetworkAvailabilityChanged; }
            catch (Exception) { }
        }
        // Unhooks the WinEvent hook and destroys the hidden broadcast window before the widget hides.
        _taskbarTracker.Dispose();
        _timer.Stop();
        _loginWatchTimer.Stop();
        _automaticUpdateTimer.Stop();
        _refreshCancellation?.Cancel();
        _updateCancellation?.Cancel();
        _codexLoginCancellation?.Cancel();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _generatedIcon?.Dispose();
        _widget.Hide();
        _details.Hide();
        _widget.AllowClose = true;
        _settingsWindow.AllowClose = true;
        _updateWindow.AllowClose = true;
        _settingsWindow.Hide();
        _onboarding.Hide();
        _updateWindow.Hide();
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    // Transient: a failure that the next refresh may well clear (network, timeout, server error).
    private sealed record ProviderResult<T>(UsageStatus Status, T? Snapshot, string Message,
        bool Transient = false, ClaudeIssue Issue = ClaudeIssue.None);
    private sealed record UpdateCheckResult(UpdateCheckStatus Status, string? Version = null);
    private enum UpdateCheckStatus { Current, Available, NotInstalled, Error }
}
