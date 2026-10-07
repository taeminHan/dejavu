using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace ClaudeUsageTray;

public partial class SettingsWindow : Window
{
    private const string OutsideTaskbarOnlyDescription = "작업표시줄 밖에 표시될 때만 적용됩니다";
    private readonly TraySettings _settings;
    // The XAML text stays the single source of the default descriptions.
    private readonly string _defaultPlacementDescription;
    private readonly string _defaultDensityDescription;
    private readonly string _defaultLayoutDescription;
    private readonly string _defaultOpacityDescription;
    private bool _loading;
    // A browser login is in progress; state updates must keep the button's pending label.
    private bool _codexLoginPending;
    // A manual update check is running; reopening the window keeps its progress row.
    private bool _updateCheckInFlight;
    private ApplicationState? _applicationState;
    private TaskbarTrackerState? _taskbarState;
    internal bool AllowClose { get; set; }

    internal SettingsWindow(TraySettings settings)
    {
        _settings = settings;
        _loading = true;
        InitializeComponent();
        _defaultPlacementDescription = PlacementDescriptionText.Text;
        _defaultDensityDescription = DensityDescriptionText.Text;
        _defaultLayoutDescription = LayoutDescriptionText.Text;
        _defaultOpacityDescription = OpacityDescriptionText.Text;

        ThemeCombo.ItemsSource = new[]
        {
            new Choice<ThemePreference>(ThemePreference.System, "시스템 설정 사용"),
            new Choice<ThemePreference>(ThemePreference.Dark, "어둡게"),
            new Choice<ThemePreference>(ThemePreference.Light, "밝게")
        };
        WidgetThemeCombo.ItemsSource = new[]
        {
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.Modern, "Modern · 기본"),
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.RetroNight, "Retro Night · 도트"),
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.FluentGlass, "Fluent Glass · 유리"),
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.TerminalMono, "Terminal Mono · 터미널"),
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.Orbit, "Orbit · 궤도"),
            new Choice<WidgetVisualTheme>(WidgetVisualTheme.PaperInk, "Paper Ink · 종이")
        };
        DensityCombo.ItemsSource = new[]
        {
            new Choice<WidgetDensity>(WidgetDensity.Small, "작음"),
            new Choice<WidgetDensity>(WidgetDensity.Compact, "중간"),
            new Choice<WidgetDensity>(WidgetDensity.Comfortable, "큼")
        };
        LayoutCombo.ItemsSource = new[]
        {
            new Choice<WidgetLayout>(WidgetLayout.SingleRow, "한 줄"),
            new Choice<WidgetLayout>(WidgetLayout.TwoRows, "두 줄 · Codex 위")
        };
        ServicesCombo.ItemsSource = new[]
        {
            new Choice<ServiceDisplayMode>(ServiceDisplayMode.AutoDetect, "자동 감지"),
            new Choice<ServiceDisplayMode>(ServiceDisplayMode.ClaudeAndCodex, "Claude + Codex"),
            new Choice<ServiceDisplayMode>(ServiceDisplayMode.ClaudeOnly, "Claude만"),
            new Choice<ServiceDisplayMode>(ServiceDisplayMode.CodexOnly, "Codex만")
        };
        PlacementCombo.ItemsSource = new[]
        {
            new Choice<WidgetPlacement>(WidgetPlacement.TaskbarRight, "작업표시줄 위 · 오른쪽"),
            new Choice<WidgetPlacement>(WidgetPlacement.InTaskbar, "작업표시줄 안 · 시계 옆"),
            new Choice<WidgetPlacement>(WidgetPlacement.TopRight, "화면 오른쪽 위"),
            new Choice<WidgetPlacement>(WidgetPlacement.Custom, "직접 배치")
        };
        RefreshCombo.ItemsSource = new[]
        {
            new Choice<int>(60, "1분마다"), new Choice<int>(120, "2분마다"), new Choice<int>(300, "5분마다")
        };
        TrayCombo.ItemsSource = new[]
        {
            new Choice<TrayIconStyle>(TrayIconStyle.ClaudeMark, "dejavu 마크"),
            new Choice<TrayIconStyle>(TrayIconStyle.Percentage, "대표 퍼센트"),
            new Choice<TrayIconStyle>(TrayIconStyle.Hidden, "숨김")
        };
        ApplyThemeStructure();
        UpdateWindowFrameAppearance();
        _loading = false;
    }

    internal event EventHandler? SettingsChanged;
    internal event EventHandler? PositionResetRequested;
    internal event EventHandler<bool>? StartupChanged;
    internal event EventHandler? UpdateCheckRequested;
    internal event EventHandler? UpdateDetailsRequested;
    internal event EventHandler? ClaudeLoginRequested;
    internal event EventHandler? CodexLoginRequested;
    internal Func<bool>? StartupStateProvider { get; set; }

    internal void ShowAndActivate()
    {
        var wasVisible = IsVisible;
        LoadValues();
        // A fresh open starts from the unchecked state. Re-activating an open window keeps a check's progress
        // or result, and so does reopening while a manual check is still running.
        if (!wasVisible && !_updateCheckInFlight)
            SetUpdateCheckResult("아직 확인하지 않았습니다.");
        if (!IsVisible) Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true;
        Topmost = false;
        Focus();
    }

    private void LoadValues()
    {
        _loading = true;
        ThemeCombo.SelectedItem = Find<ThemePreference>(ThemeCombo, _settings.Theme);
        WidgetThemeCombo.SelectedItem = Find<WidgetVisualTheme>(WidgetThemeCombo, _settings.WidgetTheme);
        UpdateThemeDescription();
        ApplyThemeStructure();
        DensityCombo.SelectedItem = Find<WidgetDensity>(DensityCombo, _settings.WidgetDensity);
        LayoutCombo.SelectedItem = Find<WidgetLayout>(LayoutCombo, _settings.WidgetLayout);
        ServicesCombo.SelectedItem = Find<ServiceDisplayMode>(ServicesCombo, _settings.ServiceDisplayMode);
        PlacementCombo.SelectedItem = Find<WidgetPlacement>(PlacementCombo, _settings.WidgetPlacement);
        RefreshCombo.SelectedItem = Find<int>(RefreshCombo, _settings.RefreshSeconds);
        TrayCombo.SelectedItem = Find<TrayIconStyle>(TrayCombo, _settings.TrayIconStyle);
        BarsToggle.IsChecked = _settings.ShowProgressBars;
        OpacitySlider.Value = _settings.WidgetOpacity * 100;
        StartupToggle.IsChecked = StartupStateProvider?.Invoke() ?? false;
        UpdateToggle.IsChecked = _settings.AutomaticUpdateChecksEnabled;
        UpdateAccentSelection();
        SaveStateText.Text = "저장됨";
        SaveStateText.SetResourceReference(TextBlock.ForegroundProperty, "MutedTextBrush");
        var currentVersion = VelopackUpdateService.CurrentVersion;
        CurrentVersionText.Text = currentVersion;
        UpdateChannelText.Text = currentVersion.Contains('-', StringComparison.Ordinal) ? "릴리스 후보 채널" : "안정 채널";
        AboutVersionText.Text = $"버전 {currentVersion}";
        UpdateStatusLabels();
        UpdateClaudeConnectionUi();
        UpdateCodexConnectionUi();
        _loading = false;
    }

    internal void UpdateClaudeConnectionState(ApplicationState state)
    {
        _applicationState = state;
        if (ClaudeConnectionTitle is not null) UpdateClaudeConnectionUi();
        if (CodexConnectionTitle is not null) UpdateCodexConnectionUi();
    }

    // The button stays enabled while a browser login is pending: a click reopens the login page
    // instead of doing nothing until the login times out.
    internal void SetCodexLoginPending(bool pending)
    {
        _codexLoginPending = pending;
        if (pending) CodexConnectionButton.Content = "브라우저 다시 열기";
        else UpdateCodexConnectionUi();
    }

    // The token, Desktop history and Ready cards render fixed text, so a failed login launch is shown
    // here; the next state update redraws the card.
    internal void ShowClaudeLoginLaunchFailed()
    {
        if (ClaudeConnectionDescription is null) return;
        ClaudeConnectionDescription.Text = "Claude 로그인 창을 열지 못했습니다. 잠시 후 다시 시도해 주세요.";
    }

    // Re-reads the Run key after the tray menu or a Settings toggle changed it.
    internal void RefreshStartupState()
    {
        var wasLoading = _loading;
        _loading = true;
        StartupToggle.IsChecked = StartupStateProvider?.Invoke() ?? false;
        UpdateStatusLabels();
        _loading = wasLoading;
    }

    private void UpdateCodexConnectionUi()
    {
        if (CodexConnectionTitle is null) return;
        var executable = CodexUsageClient.FindExecutable();
        var state = _applicationState;
        // Provider Loading means "never checked"; a refresh in flight keeps the last settled status.
        if (state is null || (state.CodexStatus == UsageStatus.Loading && state.CodexSnapshot is null))
        {
            CodexConnectionTitle.Text = "Codex 연결 확인 중";
            CodexConnectionDescription.Text = "로컬 Codex app-server에서 로그인과 사용량을 확인합니다.";
            CodexConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (state.CodexStatus is (UsageStatus.Ready or UsageStatus.Loading) && state.CodexSnapshot is not null)
        {
            CodexConnectionTitle.Text = "Codex 사용량 연결됨";
            CodexConnectionDescription.Text = "사용률, 초기화 시각과 초기화권을 공식 로컬 app-server에서 확인합니다.";
            CodexConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (executable is null)
        {
            CodexConnectionTitle.Text = CodexUsageClient.IsDesktopInstalled
                ? "Codex Desktop 업데이트 필요" : "Codex 설치 필요";
            CodexConnectionDescription.Text = CodexUsageClient.IsDesktopInstalled
                ? "호환되는 로컬 런타임을 찾지 못했습니다. Codex Desktop을 업데이트해 주세요."
                : "Codex Desktop 또는 CLI를 설치하면 dejavu가 자동으로 감지합니다.";
            ShowCodexConnectionButton("Codex 설치");
        }
        else if (state.CodexStatus == UsageStatus.LoginRequired)
        {
            CodexConnectionTitle.Text = CodexUsageClient.IsDesktopBundledExecutable(executable)
                ? "Codex Desktop 감지됨 · 로그인 필요" : "Codex 로그인 필요";
            CodexConnectionDescription.Text = "CLI를 직접 사용하지 않아도 ChatGPT 로그인으로 Codex 사용량을 연결할 수 있어요.";
            ShowCodexConnectionButton("Codex 로그인");
        }
        else if (state.CodexSnapshot is not null)
        {
            // A transient failure or timeout after a successful read is not a lost connection.
            CodexConnectionTitle.Text = "Codex 사용량 연결됨 · 확인 지연";
            CodexConnectionDescription.Text =
                $"{state.CodexMessage}. 마지막으로 확인한 사용량을 표시하고 다음 새로고침에서 다시 확인합니다.";
            CodexConnectionButton.Visibility = Visibility.Collapsed;
        }
        else
        {
            // No successful read yet: retry automatically, keeping login as a fallback.
            CodexConnectionTitle.Text = "Codex 확인 실패 · 자동 재시도";
            CodexConnectionDescription.Text = $"{state.CodexMessage}. 계속 실패하면 Codex 로그인을 다시 시도해 보세요.";
            ShowCodexConnectionButton("Codex 로그인");
        }
    }

    private void ShowCodexConnectionButton(string content)
    {
        if (!_codexLoginPending) CodexConnectionButton.Content = content;
        CodexConnectionButton.Visibility = Visibility.Visible;
    }

    // Only LoginRequired is a login problem. A transient failure after a successful read keeps the
    // connection with a delay hint; before any successful read it retries with login as a fallback.
    private void UpdateClaudeConnectionUi()
    {
        if (ClaudeConnectionTitle is null) return;
        var state = _applicationState;
        if (state?.ClaudeIssue == ClaudeIssue.TokenRefreshPending)
        {
            // Claude Code renews an expired access token itself the next time it runs; logging in
            // again is only a fallback for a revoked session.
            ClaudeConnectionTitle.Text = "Claude Code 토큰 갱신 대기";
            ClaudeConnectionDescription.Text = state.Snapshot is null
                ? "Claude Code를 한 번 실행하면 토큰이 자동으로 갱신되고 dejavu가 다시 확인합니다. 계속되면 다시 로그인해 주세요."
                : "Claude Code를 한 번 실행하면 토큰이 자동으로 갱신됩니다. 그때까지 마지막으로 확인한 사용량을 표시합니다.";
            ShowClaudeConnectionButton();
        }
        else if (state?.ClaudeStatus == UsageStatus.Ready && state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode)
        {
            ClaudeConnectionTitle.Text = "Claude Code 연결됨";
            ClaudeConnectionDescription.Text = state.Snapshot.Fable is null
                ? "5시간·주간과 초기화 시각을 표시합니다. 현재 계정 응답에는 Fable 전용 한도가 없습니다."
                : "5시간·주간·Fable 사용률과 초기화 시각을 표시합니다.";
            ClaudeConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (state?.ClaudeStatus == UsageStatus.Ready && state.Snapshot?.Source == ClaudeUsageSource.ClaudeDesktop)
        {
            var claudeCodeInstalled = ClaudeEnvironmentDetector.FindExecutable() is not null;
            ClaudeConnectionTitle.Text = "Claude Desktop 기본 사용량 연결됨";
            ClaudeConnectionDescription.Text = claudeCodeInstalled
                ? "5시간·주간은 표시 중입니다. Fable 사용량을 확인하기 위해서는 Claude Code 로그인이 필요해요."
                : "5시간·주간은 표시 중입니다. Fable 사용량을 확인하려면 Claude Code 설치와 로그인이 필요해요.";
            ClaudeConnectionButton.Content = claudeCodeInstalled ? "Claude Code 로그인" : "Claude Code 설치";
            ClaudeConnectionButton.Visibility = Visibility.Visible;
        }
        else if (state is null || state.ClaudeStatus == UsageStatus.Loading)
        {
            // Provider Loading means "never checked"; a refresh in flight keeps the last settled status.
            ClaudeConnectionTitle.Text = "Claude 연결 확인 중";
            ClaudeConnectionDescription.Text = "로컬 Claude Code 로그인과 Desktop 사용 기록을 확인합니다.";
            ClaudeConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (state.ClaudeIssue == ClaudeIssue.DesktopHistoryStale)
        {
            // No Claude Code login and Desktop has not written a recent sample: closed or idle.
            ClaudeConnectionTitle.Text = "Claude Desktop 기록 대기 중";
            ClaudeConnectionDescription.Text = ClaudeEnvironmentDetector.FindExecutable() is not null
                ? "Claude Desktop을 사용하면 5시간·주간 사용량을 자동으로 다시 표시합니다. Fable까지 확인하려면 Claude Code 로그인이 필요해요."
                : "Claude Desktop을 사용하면 5시간·주간 사용량을 자동으로 다시 표시합니다. Fable까지 확인하려면 Claude Code 설치와 로그인이 필요해요.";
            ShowClaudeConnectionButton();
        }
        else if (state.ClaudeStatus is (UsageStatus.RateLimited or UsageStatus.Offline or UsageStatus.Error) &&
                 state.Snapshot is not null)
        {
            // A transient failure after a successful read is not a lost connection.
            var desktopSource = state.Snapshot.Source == ClaudeUsageSource.ClaudeDesktop;
            ClaudeConnectionTitle.Text = desktopSource
                ? "Claude Desktop 연결됨 · 확인 지연" : "Claude Code 연결됨 · 확인 지연";
            ClaudeConnectionDescription.Text =
                $"{state.ClaudeMessage}. 마지막으로 확인한 사용량을 표시하고 다음 새로고침에서 다시 확인합니다.";
            // A Desktop source already means Claude Code is not connected: keep that upgrade path.
            if (desktopSource) ShowClaudeConnectionButton();
            else ClaudeConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (state.ClaudeStatus is UsageStatus.RateLimited or UsageStatus.Offline or UsageStatus.Error)
        {
            // No successful read yet: retry automatically, keeping login as a fallback.
            ClaudeConnectionTitle.Text = "Claude 확인 실패 · 자동 재시도";
            ClaudeConnectionDescription.Text =
                $"{state.ClaudeMessage}. 계속 실패하면 Claude Code 로그인을 다시 시도해 보세요.";
            ShowClaudeConnectionButton();
        }
        else
        {
            var claudeCodeInstalled = ClaudeEnvironmentDetector.FindExecutable() is not null;
            ClaudeConnectionTitle.Text = "Claude 연결 필요";
            ClaudeConnectionDescription.Text = claudeCodeInstalled
                ? "Fable 사용량을 확인하기 위해서는 Claude Code 로그인이 필요해요. 로그인 후 5시간·주간 사용률과 초기화 시각도 함께 확인합니다."
                : "Claude Desktop을 사용하면 5시간·주간 기본 사용량을 자동 감지합니다. Fable까지 확인하려면 Claude Code 설치와 로그인이 필요해요.";
            ClaudeConnectionButton.Content = claudeCodeInstalled ? "Claude Code 로그인" : "Claude Code 설치";
            ClaudeConnectionButton.Visibility = Visibility.Visible;
        }
    }

    private void ShowClaudeConnectionButton()
    {
        ClaudeConnectionButton.Content = ClaudeEnvironmentDetector.FindExecutable() is not null
            ? "Claude Code 로그인" : "Claude Code 설치";
        ClaudeConnectionButton.Visibility = Visibility.Visible;
    }

    private static Choice<T>? Find<T>(ItemsControl control, T value) where T : notnull =>
        control.Items.Cast<Choice<T>>().FirstOrDefault(item => EqualityComparer<T>.Default.Equals(item.Value, value));

    private void SaveAndNotify(bool applyTheme = false)
    {
        var saved = _settings.Save();
        if (applyTheme)
        {
            ThemeManager.Apply(_settings);
            ApplyThemeStructure();
            UpdateWindowFrameAppearance();
        }
        SaveStateText.Text = saved ? "저장됨" : "저장 실패";
        SaveStateText.SetResourceReference(TextBlock.ForegroundProperty, saved ? "MutedTextBrush" : "DangerBrush");
        SettingsSubtitleText.Text = saved ? "설정은 자동으로 저장됩니다"
            : "설정을 저장하지 못했습니다 · 폴더 권한과 디스크 상태를 확인해 주세요";
        UpdateStatusLabels();
        SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void UpdateStatusLabels()
    {
        SetToggleStatus(BarsStatus, _settings.ShowProgressBars);
        SetToggleStatus(StartupStatus, StartupToggle.IsChecked == true);
        SetToggleStatus(UpdateToggleStatus, _settings.AutomaticUpdateChecksEnabled);
        OpacityValue.Text = $"{OpacitySlider.Value:0}%";
        UpdatePlacementDescriptions();
    }

    internal void UpdateTaskbarStatus(TaskbarTrackerState state)
    {
        _taskbarState = state;
        UpdatePlacementDescriptions();
    }

    private void UpdatePlacementDescriptions()
    {
        if (PlacementDescriptionText is null) return;
        var inTaskbar = _settings.WidgetPlacement == WidgetPlacement.InTaskbar;
        PlacementDescriptionText.Text = inTaskbar ? TaskbarPlacementDescription(_taskbarState) : _defaultPlacementDescription;
        // Density, row layout and widget background opacity do not change the in-taskbar look; they
        // still apply to the floating fallback, so the controls stay enabled.
        DensityDescriptionText.Text = inTaskbar ? OutsideTaskbarOnlyDescription : _defaultDensityDescription;
        LayoutDescriptionText.Text = inTaskbar ? OutsideTaskbarOnlyDescription : _defaultLayoutDescription;
        OpacityDescriptionText.Text = inTaskbar ? OutsideTaskbarOnlyDescription : _defaultOpacityDescription;
    }

    private static string TaskbarPlacementDescription(TaskbarTrackerState? taskbar)
    {
        if (taskbar is not TaskbarTrackerState state) return "알림 영역 왼쪽에 표시합니다 · 드래그 이동은 지원하지 않습니다";
        return state.Status switch
        {
            TaskbarDockStatus.Docked => "알림 영역 왼쪽에 표시 중 · 드래그 이동은 지원하지 않습니다",
            TaskbarDockStatus.Suppressed when state.Reason == "fullscreen" => "전체 화면 앱이 실행 중이라 잠시 숨겼습니다",
            TaskbarDockStatus.Suppressed => "작업표시줄 위치를 확인하는 중입니다",
            TaskbarDockStatus.Fallback =>
                "작업표시줄 안에 넣을 수 없어 작업표시줄 위에 표시합니다 (" + TaskbarFallbackReason(state.Reason) + ")",
            _ => "알림 영역 왼쪽에 표시합니다 · 드래그 이동은 지원하지 않습니다"
        };
    }

    private static string TaskbarFallbackReason(string? reason) => reason switch
    {
        "autohide" => "자동 숨기기",
        "vertical" => "세로 작업표시줄",
        "non_xaml_taskbar" => "지원하지 않는 작업표시줄",
        "taskbar_missing" => "작업표시줄 없음",
        "tray_missing" => "알림 영역 없음",
        "rtl_or_mirrored" => "오른쪽→왼쪽 배치",
        "band_too_small" => "작업표시줄이 너무 낮음",
        "shell_mismatch" => "다른 셸 사용 중",
        _ => "지원하지 않는 환경"
    };

    private static void SetToggleStatus(TextBlock label, bool enabled)
    {
        label.Text = enabled ? "켜짐" : "꺼짐";
        label.SetResourceReference(TextBlock.ForegroundProperty, enabled ? "AccentBrush" : "TextBrush");
    }

    private void OnNavigationChanged(object sender, RoutedEventArgs e)
    {
        if (DisplayPanel is null || ConnectionsPanel is null || AppearancePanel is null) return;
        DisplayPanel.Visibility = DisplayNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        AppearancePanel.Visibility = AppearanceNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        ConnectionsPanel.Visibility = ConnectionsNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        BehaviorPanel.Visibility = BehaviorNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        UpdatePanel.Visibility = UpdateNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PrivacyPanel.Visibility = PrivacyNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ThemeCombo.SelectedItem is not Choice<ThemePreference> choice) return;
        _settings.Theme = choice.Value;
        SaveAndNotify(applyTheme: true);
    }

    private void OnDensityChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || DensityCombo.SelectedItem is not Choice<WidgetDensity> choice) return;
        _settings.WidgetDensity = choice.Value;
        SaveAndNotify();
    }

    private void OnLayoutChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LayoutCombo.SelectedItem is not Choice<WidgetLayout> choice) return;
        _settings.WidgetLayout = choice.Value;
        SaveAndNotify();
    }

    private void OnServicesChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ServicesCombo.SelectedItem is not Choice<ServiceDisplayMode> choice) return;
        _settings.ServiceDisplayMode = choice.Value;
        SaveAndNotify();
    }

    private void OnTitleBarMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        if (e.ClickCount == 2)
        {
            ToggleMaximize();
            return;
        }
        try { DragMove(); } catch (InvalidOperationException) { }
    }

    private void OnMinimizeClick(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnMaximizeClick(object sender, RoutedEventArgs e) => ToggleMaximize();

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void OnWindowStateChanged(object? sender, EventArgs e) => UpdateWindowFrameAppearance();

    private void UpdateWindowFrameAppearance()
        => UpdateWindowFrameAppearance(VisualTreeHelper.GetDpi(this));

    private void UpdateWindowFrameAppearance(DpiScale dpi)
    {
        if (WindowFrame is null) return;
        var maximized = WindowState == WindowState.Maximized;
        var configuredRadius = TryFindResource("WindowCornerRadius") is CornerRadius corners
            ? corners.TopLeft
            : 12d;
        var configuredThickness = TryFindResource("WindowFrameThickness") is Thickness thickness
            ? thickness
            : new Thickness(1);
        var frameThickness = Math.Max(
            Math.Max(configuredThickness.Left, configuredThickness.Top),
            Math.Max(configuredThickness.Right, configuredThickness.Bottom));
        var scale = Math.Max(dpi.DpiScaleX, 1d);
        // WindowChrome forwards its radius as the Win32 rounded-region ellipse width,
        // while Border uses a stroke-center radius. Match those geometries in physical pixels.
        var strokePixels = Math.Round(frameThickness * scale);
        var nativeRadiusPixels = Math.Ceiling(configuredRadius * scale) / 2d;
        var insetPixels = maximized || nativeRadiusPixels <= 1d + (strokePixels / 2d)
            ? 0d
            : 1d;
        var inset = insetPixels / scale;
        var radius = maximized
            ? 0d
            : Math.Max(0d, (nativeRadiusPixels - insetPixels - (strokePixels / 2d)) / scale);

        WindowFrame.Margin = new Thickness(inset);
        WindowFrame.CornerRadius = new CornerRadius(radius);
        WindowFrame.BorderThickness = maximized ? new Thickness(0) : configuredThickness;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        UpdateWindowFrameAppearance();
    }

    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        UpdateWindowFrameAppearance(newDpi);
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Hide();

    private void OnPlacementChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || PlacementCombo.SelectedItem is not Choice<WidgetPlacement> choice) return;
        _settings.WidgetPlacement = choice.Value;
        if (choice.Value != WidgetPlacement.Custom)
        {
            _settings.WidgetLeft = null;
            _settings.WidgetTop = null;
        }
        SaveAndNotify();
        PositionResetRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnRefreshChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || RefreshCombo.SelectedItem is not Choice<int> choice) return;
        _settings.RefreshSeconds = choice.Value;
        SaveAndNotify();
    }

    private void OnTrayChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || TrayCombo.SelectedItem is not Choice<TrayIconStyle> choice) return;
        _settings.TrayIconStyle = choice.Value;
        SaveAndNotify();
    }

    private void OnToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _settings.ShowProgressBars = BarsToggle.IsChecked == true;
        SaveAndNotify();
    }

    private void OnOpacityChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (OpacityValue is null) return;
        OpacityValue.Text = $"{e.NewValue:0}%";
        if (_loading) return;
        _settings.WidgetOpacity = e.NewValue / 100d;
        SaveAndNotify();
    }

    private void UpdateAccentSelection()
    {
        foreach (var button in new[] { BlueAccent, PurpleAccent, CoralAccent, GreenAccent })
            button.IsChecked = string.Equals(button.Tag as string, _settings.AccentColor,
                StringComparison.OrdinalIgnoreCase);
    }

    private void OnAccentChanged(object sender, RoutedEventArgs e)
    {
        if (_loading || sender is not System.Windows.Controls.RadioButton
            { IsChecked: true, Tag: string color }) return;
        _settings.AccentColor = color;
        SaveAndNotify(applyTheme: true);
    }

    private void OnWidgetThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || WidgetThemeCombo.SelectedItem is not Choice<WidgetVisualTheme> choice) return;
        _settings.WidgetTheme = choice.Value;
        UpdateThemeDescription();
        SaveAndNotify(applyTheme: true);
    }

    private void UpdateThemeDescription()
    {
        if (ThemeDescriptionText is null) return;
        ThemeDescriptionText.Text = _settings.WidgetTheme switch
        {
            WidgetVisualTheme.RetroNight => "픽셀 글꼴, 각진 프레임과 분할 게이지를 사용합니다",
            WidgetVisualTheme.FluentGlass => "반투명 레이어와 부드러운 캡슐형 컨트롤을 사용합니다",
            WidgetVisualTheme.TerminalMono => "고정폭 정렬과 터미널형 선·게이지를 사용합니다",
            WidgetVisualTheme.Orbit => "원형 계기와 선명한 궤도형 상태 표시를 사용합니다",
            WidgetVisualTheme.PaperInk => "종이 질감과 색연필형 그래프를 사용합니다",
            _ => "기본 테마입니다"
        };
    }

    private void ApplyThemeStructure()
    {
        if (SettingsShell is null) return;
        var theme = _settings.WidgetTheme;
        // Navigation meaning and hit targets stay stable across themes. Themes
        // still own surface/row treatment, but must not replace icons with text glyphs.
        SettingsTitleRow.Height = new GridLength(68);
        SettingsSidebarColumn.Width = new GridLength(184);
        SettingsTextureOverlay.Visibility = theme is WidgetVisualTheme.RetroNight
            or WidgetVisualTheme.TerminalMono or WidgetVisualTheme.PaperInk
            ? Visibility.Visible : Visibility.Collapsed;
        SettingsTextureOverlay.Opacity = theme == WidgetVisualTheme.TerminalMono ? 0.22
            : theme == WidgetVisualTheme.PaperInk ? 0.16 : 0.12;

        SettingsBrandText.Text = "Dejavu";
        SettingsSubtitleText.Text = "설정은 자동으로 저장됩니다";

        SettingsTitleBar.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty,
            theme is WidgetVisualTheme.TerminalMono or WidgetVisualTheme.PaperInk ? "BackgroundBrush" : "SurfaceBrush");
        SettingsSidebar.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty,
            theme is WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono or WidgetVisualTheme.PaperInk
                ? "BackgroundBrush" : "SurfaceBrush");
        SettingsSidebar.Padding = theme switch
        {
            WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit => new Thickness(14, 22, 14, 22),
            WidgetVisualTheme.TerminalMono => new Thickness(10, 14, 10, 14),
            WidgetVisualTheme.PaperInk => new Thickness(8, 22, 8, 22),
            _ => new Thickness(12, 18, 12, 18)
        };
        var contentPadding = theme switch
        {
            WidgetVisualTheme.FluentGlass => new Thickness(28, 26, 22, 26),
            WidgetVisualTheme.TerminalMono => new Thickness(22, 20, 22, 20),
            WidgetVisualTheme.Orbit => new Thickness(30, 26, 24, 26),
            WidgetVisualTheme.PaperInk => new Thickness(34, 26, 24, 26),
            _ => new Thickness(28, 24, 28, 24)
        };
        foreach (var panel in new[] { DisplayPanel, AppearancePanel, ConnectionsPanel, BehaviorPanel, UpdatePanel, PrivacyPanel })
            panel.Padding = contentPadding;

        var rowStyle = TryFindResource("SettingRow") as Style;
        foreach (var row in FindVisualChildren<System.Windows.Controls.Border>(SettingsContent)
                     .Where(borderElement => ReferenceEquals(borderElement.Style, rowStyle)))
        {
            row.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "BorderBrush");
            row.Margin = theme switch
            {
                WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit => new Thickness(0, 0, 0, 8),
                WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono => new Thickness(0, 0, 0, 5),
                _ => new Thickness(0)
            };
            row.CornerRadius = theme switch
            {
                WidgetVisualTheme.FluentGlass => new CornerRadius(12),
                WidgetVisualTheme.Orbit => new CornerRadius(14),
                WidgetVisualTheme.PaperInk => new CornerRadius(0),
                _ => new CornerRadius(ThemeManager.UsesAngularChrome(theme) ? 0 : 6)
            };
            row.BorderThickness = theme switch
            {
                WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit => new Thickness(1),
                WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono => new Thickness(1),
                _ => new Thickness(0, 0, 0, 1)
            };
            if (theme is WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit)
                row.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "SurfaceBrush");
            else row.Background = System.Windows.Media.Brushes.Transparent;
        }
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject root) where T : DependencyObject
    {
        for (var index = 0; index < System.Windows.Media.VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(root, index);
            if (child is T match) yield return match;
            foreach (var descendant in FindVisualChildren<T>(child)) yield return descendant;
        }
    }

    private void OnStartupChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        UpdateStatusLabels();
        StartupChanged?.Invoke(this, StartupToggle.IsChecked == true);
    }

    private void OnUpdateToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _settings.AutomaticUpdateChecksEnabled = UpdateToggle.IsChecked == true;
        SaveAndNotify();
    }

    internal void SetUpdateCheckLoading()
    {
        _updateCheckInFlight = true;
        UpdateCheckProgress.Visibility = Visibility.Visible;
        UpdateCheckStatus.Text = "새 버전을 확인하는 중입니다…";
        CheckUpdatesButton.Content = "확인 중";
        CheckUpdatesButton.Tag = null;
        CheckUpdatesButton.IsEnabled = false;
    }

    internal void SetUpdateCheckResult(string message, bool updateAvailable = false)
    {
        _updateCheckInFlight = false;
        UpdateCheckProgress.Visibility = Visibility.Collapsed;
        UpdateCheckStatus.Text = message;
        CheckUpdatesButton.Content = updateAvailable ? "업데이트 보기" : "업데이트 확인";
        CheckUpdatesButton.Tag = updateAvailable ? "details" : null;
        CheckUpdatesButton.IsEnabled = true;
    }

    private void OnCheckUpdates(object sender, RoutedEventArgs e)
    {
        if (Equals(CheckUpdatesButton.Tag, "details"))
        {
            UpdateDetailsRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        SetUpdateCheckLoading();
        UpdateCheckRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnClaudeLoginClick(object sender, RoutedEventArgs e) =>
        ClaudeLoginRequested?.Invoke(this, EventArgs.Empty);

    private void OnCodexLoginClick(object sender, RoutedEventArgs e) =>
        CodexLoginRequested?.Invoke(this, EventArgs.Empty);

    private void OnResetPosition(object sender, RoutedEventArgs e)
    {
        _settings.WidgetPlacement = WidgetPlacement.TaskbarRight;
        _settings.WidgetLeft = null;
        _settings.WidgetTop = null;
        SaveAndNotify();
        LoadValues();
        PositionResetRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnRestoreDefaults(object sender, RoutedEventArgs e)
    {
        _settings.WidgetOpacity = 0.9;
        _settings.BackgroundColor = "#1E1E20";
        _settings.AccentColor = "#6D8EFF";
        _settings.TextColor = "#AEAEB4";
        _settings.UseThresholdColors = true;
        _settings.ShowProgressBars = true;
        _settings.RefreshSeconds = 60;
        _settings.TrayIconStyle = TrayIconStyle.ClaudeMark;
        _settings.WidgetDensity = WidgetDensity.Compact;
        _settings.WidgetLayout = WidgetLayout.SingleRow;
        _settings.ServiceDisplayMode = ServiceDisplayMode.AutoDetect;
        _settings.WidgetPlacement = WidgetPlacement.TaskbarRight;
        _settings.Theme = ThemePreference.System;
        _settings.WidgetTheme = WidgetVisualTheme.Modern;
        _settings.AutomaticUpdateChecksEnabled = true;
        _settings.WidgetLeft = null;
        _settings.WidgetTop = null;
        SaveAndNotify(applyTheme: true);
        LoadValues();
        PositionResetRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnOpenDiagnostics(object sender, RoutedEventArgs e)
    {
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");
            Directory.CreateDirectory(directory);
            Process.Start(new ProcessStartInfo("explorer.exe", directory) { UseShellExecute = true });
        }
        catch
        {
            SettingsSubtitleText.Text = "진단 폴더를 열지 못했습니다";
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (AllowClose) return;
        e.Cancel = true;
        Hide();
    }

    private sealed record Choice<T>(T Value, string Label)
    {
        public override string ToString() => Label;
    }
}
