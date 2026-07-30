using System.Drawing.Drawing2D;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
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
    private readonly Forms.NotifyIcon _trayIcon = new();
    private readonly DispatcherTimer _timer = new();
    private readonly DispatcherTimer _loginWatchTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private CancellationTokenSource? _refreshCancellation;
    private ApplicationState _state = ApplicationState.Loading();
    private Drawing.Icon? _generatedIcon;
    private bool _refreshing;
    private bool _disposed;

    public DesktopApplicationController(System.Windows.Application application, bool startWithSettings = false,
        bool startWithOnboarding = false)
    {
        _application = application;
        ThemeManager.Apply(_settings);

        _widget = new UsageWidgetWindow(_settings);
        _settingsWindow = new SettingsWindow(_settings)
        {
            StartupStateProvider = IsStartupEnabled
        };
        _onboarding = new OnboardingWindow(_settings);

        WireWindows();
        ConfigureTray();
        _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
        _timer.Tick += async (_, _) => await RefreshAsync();
        _timer.Start();
        _loginWatchTimer.Tick += async (_, _) =>
        {
            _onboarding.RefreshDetection();
            if (!ClaudeUsageClient.HasCredentialFile()) return;
            _loginWatchTimer.Stop();
            await RefreshAsync(force: true);
        };
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;

        if (startWithSettings)
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

        AppDiagnostics.ClearCrashLog();
        _ = RefreshAsync();
    }

    private void WireWindows()
    {
        _widget.WidgetClicked += (_, _) => ToggleDetails();
        _widget.SettingsRequested += (_, _) => ShowSettings();
        _widget.PositionChangedByUser += (_, _) => _settings.Save();

        _details.RefreshRequested += async (_, _) => await RefreshAsync(force: true);
        _details.SettingsRequested += (_, _) => ShowSettings();
        _details.LoginRequested += (_, _) => StartClaudeLogin();

        _settingsWindow.SettingsChanged += (_, _) => ApplySettings();
        _settingsWindow.PositionResetRequested += (_, _) => _widget.PositionFromSettings(forceDefault: true);
        _settingsWindow.StartupChanged += (_, enabled) => SetStartup(enabled);

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
        _onboarding.LoginRequested += (_, _) => StartClaudeLogin();
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
        menu.Items.Add("지금 새로고침", null, async (_, _) => await _application.Dispatcher.InvokeAsync(async () => await RefreshAsync(force: true)));
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
        UpdateTrayIcon();
    }

    private async Task RefreshAsync(bool force = false)
    {
        if (_refreshing) return;

        _refreshing = true;
        _refreshCancellation = new CancellationTokenSource();
        ApplyState(ApplicationState.Loading(_state.Snapshot, _state.CodexSnapshot));
        try
        {
            var claudeTask = ReadClaudeAsync(_refreshCancellation.Token);
            var codexTask = ReadCodexAsync(_refreshCancellation.Token);
            await Task.WhenAll(claudeTask, codexTask);
            var claude = await claudeTask;
            var codex = await codexTask;
            _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
            var overall = claude.Status == UsageStatus.Ready || codex.Status == UsageStatus.Ready
                ? UsageStatus.Ready
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
        catch (OperationCanceledException) when (_refreshCancellation.IsCancellationRequested)
        {
            // A manual refresh superseded the current request.
        }
        catch (Exception)
        {
            ApplyState(_state with { Status = UsageStatus.Error, Message = "사용량을 가져오지 못했어요" });
        }
        finally
        {
            _refreshCancellation.Dispose();
            _refreshCancellation = null;
            _refreshing = false;
        }
    }

    private async Task<ProviderResult<UsageSnapshot>> ReadClaudeAsync(CancellationToken cancellationToken)
    {
        try
        {
            var snapshot = await _claudeClient.GetUsageAsync(cancellationToken);
            return new ProviderResult<UsageSnapshot>(UsageStatus.Ready, snapshot, "Claude 최신");
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
        _state = state;
        if (state.ClaudeStatus == UsageStatus.LoginRequired) _loginWatchTimer.Start();
        else if (state.ClaudeStatus == UsageStatus.Ready) _loginWatchTimer.Stop();
        _widget.UpdateState(state);
        _details.UpdateState(state, _settings);
        UpdateTrayIcon();
        AppDiagnostics.Write(state, _widget);
    }

    private void ApplySettings()
    {
        ThemeManager.Apply(_settings);
        _widget.ApplySettings(_settings);
        if (_settings.WidgetPlacement != WidgetPlacement.Custom) _widget.PositionFromSettings(forceDefault: true);
        else
        {
            _widget.KeepCurrentPositionVisible();
            _settings.Save();
        }
        _details.UpdateState(_state, _settings);
        _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
        UpdateTrayIcon();
        AppDiagnostics.Write(_state, _widget);
    }

    private void ShowWidget()
    {
        _widget.PositionFromSettings();
        if (!_widget.IsVisible) _widget.Show();
        _widget.Topmost = true;
    }

    private void ToggleDetails()
    {
        if (_details.IsVisible) _details.Hide();
        else
        {
            _details.UpdateState(_state, _settings);
            _details.ShowNear(_widget);
        }
    }

    private void ShowSettings()
    {
        _details.Hide();
        _settingsWindow.ShowAndActivate();
    }

    private void StartClaudeLogin()
    {
        var environment = ClaudeEnvironmentDetector.Detect();
        if (environment.IsInstalled) ClaudeEnvironmentDetector.OpenLogin();
        else ClaudeEnvironmentDetector.OpenSetupPage();
        _loginWatchTimer.Start();
        _onboarding.RefreshDetection();
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

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) =>
        _application.Dispatcher.Invoke(() => _widget.PositionFromSettings());

    private void Exit()
    {
        Dispose();
        _application.Shutdown();
    }

    private static bool IsStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
        return key?.GetValue(RunValueName) is string;
    }

    private static void SetStartup(bool enabled)
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
        _timer.Stop();
        _loginWatchTimer.Stop();
        _refreshCancellation?.Cancel();
        _refreshCancellation?.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _generatedIcon?.Dispose();
        _widget.Hide();
        _details.Hide();
        _settingsWindow.Hide();
        _onboarding.Hide();
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    private sealed record ProviderResult<T>(UsageStatus Status, T? Snapshot, string Message);
}
