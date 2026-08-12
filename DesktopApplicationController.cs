using System.Drawing.Drawing2D;
using System.Net.Http;
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
    private CancellationTokenSource? _refreshCancellation;
    private CancellationTokenSource? _updateCancellation;
    private CancellationTokenSource? _codexLoginCancellation;
    private UpdateInfo? _pendingUpdate;
    private Task<UpdateCheckResult>? _updateCheckTask;
    private DateTimeOffset? _nextAutomaticUpdateAt;
    private ApplicationState _state = ApplicationState.Loading();
    private Drawing.Icon? _generatedIcon;
    private bool _loginWatchRequiresClaudeCode;
    private bool _codexLoginInProgress;
    private bool _disposed;

    public DesktopApplicationController(System.Windows.Application application, bool startWithSettings = false,
        bool startWithOnboarding = false, bool startWithDetails = false,
        WidgetVisualTheme? previewTheme = null, WidgetDensity? previewDensity = null,
        WidgetLayout? previewLayout = null, ServiceDisplayMode? previewServices = null,
        bool? previewProgress = null)
    {
        _application = application;
        if (previewTheme is not null) _settings.WidgetTheme = previewTheme.Value;
        if (previewDensity is not null) _settings.WidgetDensity = previewDensity.Value;
        if (previewLayout is not null) _settings.WidgetLayout = previewLayout.Value;
        if (previewServices is not null) _settings.ServiceDisplayMode = previewServices.Value;
        if (previewProgress is not null) _settings.ShowProgressBars = previewProgress.Value;
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
        _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
        _timer.Tick += async (_, _) =>
        {
            if (!_disposed) await RefreshAsync();
        };
        _timer.Start();
        _loginWatchTimer.Tick += async (_, _) =>
        {
            if (_disposed) return;
            _onboarding.RefreshDetection();
            // The login watcher must not repeatedly cancel a slow provider request.
            // A non-forced refresh coalesces with one already in progress.
            await RefreshAsync();
            if (_disposed) return;
            var connected = _state.ClaudeStatus == UsageStatus.Ready &&
                            (!_loginWatchRequiresClaudeCode ||
                             _state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode);
            if (connected) _loginWatchTimer.Stop();
        };
        _automaticUpdateTimer.Tick += OnAutomaticUpdateTimerTick;
        ConfigureAutomaticUpdateChecks();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.TimeChanged += OnSystemTimeChanged;

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

        _details.RefreshRequested += async (_, _) => await RefreshAsync(force: true);
        _details.SettingsRequested += (_, _) => ShowSettings();
        _details.ClaudeLoginRequested += (_, _) => StartClaudeLogin(requireClaudeCode: true);
        _details.CodexLoginRequested += async (_, _) => await StartCodexLoginAsync();

        _settingsWindow.SettingsChanged += (_, _) => ApplySettings();
        _settingsWindow.PositionResetRequested += (_, _) => _widget.PositionFromSettings(forceDefault: true);
        _settingsWindow.StartupChanged += (_, enabled) => SetStartup(enabled);
        _settingsWindow.UpdateCheckRequested += async (_, _) => await CheckForUpdatesFromSettingsAsync();
        _settingsWindow.UpdateDetailsRequested += (_, _) => ShowPendingUpdate();
        _settingsWindow.ClaudeLoginRequested += (_, _) => StartClaudeLogin(requireClaudeCode: true);
        _settingsWindow.CodexLoginRequested += async (_, _) => await StartCodexLoginAsync();

        _updateWindow.InstallRequested += async (_, _) => await DownloadAndApplyUpdateAsync();

        _onboarding.Completed += (_, _) =>
        {
            ShowWidget();
            ApplyState(_state);
        };
        _onboarding.PrivacyRequested += (_, _) =>
        {
            _onboarding.Hide();
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
            await InvokeOnDispatcherAsync(() => RefreshAsync(force: true)));
        menu.Items.Add("업데이트 확인", null, async (_, _) =>
            await InvokeOnDispatcherAsync(() => CheckForUpdatesAsync(showIfCurrent: true)));
        menu.Items.Add("설정", null, (_, _) => _application.Dispatcher.Invoke(ShowSettings));
        menu.Items.Add(new Forms.ToolStripSeparator());
        var startup = new Forms.ToolStripMenuItem("Windows 시작 시 실행") { Checked = IsStartupEnabled(), CheckOnClick = true };
        startup.CheckedChanged += (_, _) => SetStartup(startup.Checked);
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

    private async Task RefreshAsync(bool force = false)
    {
        if (_disposed) return;
        if (force)
        {
            try { _refreshCancellation?.Cancel(); }
            catch (ObjectDisposedException) { }
        }

        if (!await _refreshGate.WaitAsync(0))
        {
            if (!force) return;
            await _refreshGate.WaitAsync();
        }

        CancellationTokenSource? refreshCancellation = null;
        try
        {
            if (_disposed) return;
            refreshCancellation = new CancellationTokenSource();
            _refreshCancellation = refreshCancellation;
            ApplyState(ApplicationState.Loading(_state.Snapshot, _state.CodexSnapshot));
            var claudeTask = ReadClaudeAsync(refreshCancellation.Token);
            var codexTask = ReadCodexAsync(refreshCancellation.Token);
            await Task.WhenAll(claudeTask, codexTask);
            if (_disposed || refreshCancellation.IsCancellationRequested) return;
            var claude = await claudeTask;
            var codex = await codexTask;
            _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
            var overall = claude.Status == UsageStatus.Ready || codex.Status == UsageStatus.Ready
                ? UsageStatus.Ready
                : claude.Status == UsageStatus.RateLimited || codex.Status == UsageStatus.RateLimited
                    ? UsageStatus.RateLimited
                    : claude.Status == UsageStatus.Offline || codex.Status == UsageStatus.Offline
                        ? UsageStatus.Offline
                    : claude.Status == UsageStatus.LoginRequired && codex.Status == UsageStatus.LoginRequired
                        ? UsageStatus.LoginRequired : UsageStatus.Error;
            var message = claude.Status == UsageStatus.Ready && codex.Status == UsageStatus.Ready
                ? "Claude · Codex 사용량이 최신 상태입니다"
                : $"{claude.Message} · {codex.Message}";
            ApplyState(new ApplicationState(overall, claude.Snapshot, message, DateTimeOffset.Now,
                CodexSnapshot: codex.Snapshot, ClaudeStatus: claude.Status, CodexStatus: codex.Status,
                ClaudeMessage: claude.Message, CodexMessage: codex.Message));
        }
        catch (OperationCanceledException) when (refreshCancellation?.IsCancellationRequested == true)
        {
            // A manual refresh superseded the current request.
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
        if (_disposed || !_settings.AutomaticUpdateChecksEnabled) return;
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
                _updateWindow.ShowCurrent();
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
            var update = await _updateService.CheckAsync();
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
            _pendingUpdate = null;
            return new UpdateCheckResult(UpdateCheckStatus.Error);
        }
    }

    private void ShowPendingUpdate()
    {
        if (_pendingUpdate is null) return;
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
        if (_pendingUpdate is null || _updateCancellation is not null) return;
        var updateCancellation = new CancellationTokenSource();
        _updateCancellation = updateCancellation;
        try
        {
            _updateWindow.SetDownloading(0);
            await _updateService.DownloadAsync(_pendingUpdate,
                progress =>
                {
                    if (_disposed || updateCancellation.IsCancellationRequested) return;
                    _application.Dispatcher.BeginInvoke(() =>
                    {
                        if (!_disposed && !updateCancellation.IsCancellationRequested)
                            _updateWindow.SetDownloading(progress);
                    });
                },
                updateCancellation.Token);
            if (_disposed || updateCancellation.IsCancellationRequested) return;
            _updateWindow.SetDownloading(100);
            _updateService.ApplyAndRestart(_pendingUpdate);
            Exit();
        }
        catch (OperationCanceledException) when (updateCancellation.IsCancellationRequested)
        {
            if (!_disposed) _updateWindow.SetError("업데이트가 취소되었습니다.");
        }
        catch (Exception)
        {
            if (!_disposed) _updateWindow.SetError("업데이트를 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.");
        }
        finally
        {
            if (ReferenceEquals(_updateCancellation, updateCancellation)) _updateCancellation = null;
            updateCancellation.Dispose();
        }
    }

    private async Task<ProviderResult<UsageSnapshot>> ReadClaudeAsync(CancellationToken cancellationToken)
    {
        try
        {
            var snapshot = await _claudeClient.GetUsageAsync(cancellationToken);
            var message = snapshot.Source == ClaudeUsageSource.ClaudeDesktop
                ? "Claude Desktop 기록" : "Claude 최신";
            return new ProviderResult<UsageSnapshot>(UsageStatus.Ready, snapshot, message);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (ClaudeLoginRequiredException)
        {
            return new ProviderResult<UsageSnapshot>(UsageStatus.LoginRequired, _state.Snapshot, "Claude 로그인 필요");
        }
        catch (ClaudeRateLimitException)
        {
            return new ProviderResult<UsageSnapshot>(UsageStatus.RateLimited, _state.Snapshot, "Claude 자동 재시도");
        }
        catch (HttpRequestException)
        {
            return new ProviderResult<UsageSnapshot>(UsageStatus.Offline, _state.Snapshot, "Claude 오프라인");
        }
        catch
        {
            return new ProviderResult<UsageSnapshot>(UsageStatus.Error, _state.Snapshot, "Claude 확인 실패");
        }
    }

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
        catch (CodexLoginRequiredException)
        {
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.LoginRequired, _state.CodexSnapshot, "Codex 로그인 필요");
        }
        catch (CodexCliUnavailableException)
        {
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.Error, _state.CodexSnapshot, "Codex CLI 필요");
        }
        catch
        {
            return new ProviderResult<CodexUsageSnapshot>(UsageStatus.Error, _state.CodexSnapshot, "Codex 확인 실패");
        }
    }

    private void ApplyState(ApplicationState state)
    {
        if (_disposed) return;
        _state = state;
        if (state.ClaudeStatus == UsageStatus.LoginRequired) _loginWatchTimer.Start();
        else if (state.ClaudeStatus == UsageStatus.Ready &&
                 (!_loginWatchTimer.IsEnabled || !_loginWatchRequiresClaudeCode ||
                  state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode))
            _loginWatchTimer.Stop();
        _widget.UpdateState(state);
        _details.UpdateState(state, _settings);
        _settingsWindow.UpdateClaudeConnectionState(state);
        _onboarding.UpdateState(state);
        UpdateTrayIcon();
        AppDiagnostics.Write(state, _widget, _settings.WidgetOpacity);
    }

    private void ApplySettings()
    {
        if (_disposed) return;
        ThemeManager.Apply(_settings);
        _widget.ApplySettings(_settings);
        _updateWindow.ApplyTheme(_settings.WidgetTheme);
        _onboarding.ApplyTheme(_settings.WidgetTheme);
        if (_settings.WidgetPlacement != WidgetPlacement.Custom) _widget.PositionFromSettings(forceDefault: true);
        else
        {
            _widget.KeepCurrentPositionVisible();
            _settings.Save();
        }
        _details.UpdateState(_state, _settings);
        _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
        ConfigureAutomaticUpdateChecks();
        UpdateTrayIcon();
        AppDiagnostics.Write(_state, _widget, _settings.WidgetOpacity);
    }

    private void ShowWidget()
    {
        if (_disposed) return;
        _widget.PositionFromSettings();
        if (!_widget.IsVisible) _widget.Show();
        _widget.RequestTopmostRepair("show_widget");
    }

    private void ToggleDetails()
    {
        if (_disposed) return;
        if (_details.IsVisible) _details.Hide();
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
            _loginWatchTimer.Start();
            _onboarding.RefreshDetection();
        }
        catch
        {
            ApplyState(_state with
            {
                ClaudeStatus = UsageStatus.Error,
                ClaudeMessage = "Claude 로그인 창을 열지 못했습니다"
            });
        }
    }

    private async Task StartCodexLoginAsync()
    {
        if (_codexLoginInProgress) return;
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
            await _codexClient.LoginAsync(codexLoginCancellation.Token);
            if (_disposed || codexLoginCancellation.IsCancellationRequested) return;
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
            ApplyState(_state with
            {
                CodexStatus = UsageStatus.LoginRequired,
                CodexMessage = "Codex 로그인을 완료하지 못했습니다"
            });
        }
        catch
        {
            ApplyState(_state with
            {
                CodexStatus = UsageStatus.Error,
                CodexMessage = "Codex 로그인 창을 열지 못했습니다"
            });
        }
        finally
        {
            _codexLoginInProgress = false;
            if (ReferenceEquals(_codexLoginCancellation, codexLoginCancellation)) _codexLoginCancellation = null;
            codexLoginCancellation.Dispose();
            if (!_disposed)
            {
                _onboarding.SetCodexLoginPending(false);
                _settingsWindow.SetCodexLoginPending(false);
            }
        }
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
            ? _state.CodexSnapshot?.Weekly ?? _state.CodexSnapshot?.FiveHour
            : _settings.PrimaryMetric switch
        {
            PrimaryMetric.Weekly => _state.Snapshot?.Weekly,
            PrimaryMetric.Fable => _state.Snapshot?.Fable,
            PrimaryMetric.Codex => _state.CodexSnapshot?.Weekly ?? _state.CodexSnapshot?.FiveHour,
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
        if (showCodex) providers.Add($"Codex {Format(_state.CodexSnapshot?.Weekly ?? _state.CodexSnapshot?.FiveHour)}");
        _trayIcon.Text = Truncate(providers.Count == 0 ? "dejavu · 연결된 서비스 없음"
            : $"dejavu · {string.Join(" · ", providers)}", 63);
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e)
        => QueueWidgetTopmostRepair("display_settings_changed", reposition: true);

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume) return;
        QueueWidgetTopmostRepair("power_resume");
        QueueAutomaticUpdateScheduleRecovery(checkIfOverdue: true);
    }

    private void OnSystemTimeChanged(object? sender, EventArgs e) =>
        QueueAutomaticUpdateScheduleRecovery(checkIfOverdue: true);

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.SessionLogon
            or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)
        {
            QueueWidgetTopmostRepair($"session_{e.Reason}");
        }
    }

    private void QueueWidgetTopmostRepair(string reason, bool reposition = false)
    {
        if (_disposed || _application.Dispatcher.HasShutdownStarted) return;
        _application.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() =>
        {
            if (_disposed) return;
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
        _settingsWindow.AllowClose = true;
        _updateWindow.AllowClose = true;
        _settingsWindow.Hide();
        _onboarding.Hide();
        _updateWindow.Hide();
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    private sealed record ProviderResult<T>(UsageStatus Status, T? Snapshot, string Message);
    private sealed record UpdateCheckResult(UpdateCheckStatus Status, string? Version = null);
    private enum UpdateCheckStatus { Current, Available, NotInstalled, Error }
}
