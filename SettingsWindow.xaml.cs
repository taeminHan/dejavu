using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace ClaudeUsageTray;

public partial class SettingsWindow : Window
{
    private readonly TraySettings _settings;
    private bool _loading;
    private ApplicationState? _applicationState;

    internal SettingsWindow(TraySettings settings)
    {
        _settings = settings;
        _loading = true;
        InitializeComponent();

        ThemeCombo.ItemsSource = new[]
        {
            new Choice<ThemePreference>(ThemePreference.System, "시스템 설정 사용"),
            new Choice<ThemePreference>(ThemePreference.Dark, "어둡게"),
            new Choice<ThemePreference>(ThemePreference.Light, "밝게")
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
        LoadValues();
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
        DensityCombo.SelectedItem = Find<WidgetDensity>(DensityCombo, _settings.WidgetDensity);
        LayoutCombo.SelectedItem = Find<WidgetLayout>(LayoutCombo, _settings.WidgetLayout);
        ServicesCombo.SelectedItem = Find<ServiceDisplayMode>(ServicesCombo, _settings.ServiceDisplayMode);
        PlacementCombo.SelectedItem = Find<WidgetPlacement>(PlacementCombo, _settings.WidgetPlacement);
        RefreshCombo.SelectedItem = Find<int>(RefreshCombo, _settings.RefreshSeconds);
        TrayCombo.SelectedItem = Find<TrayIconStyle>(TrayCombo, _settings.TrayIconStyle);
        BarsToggle.IsChecked = _settings.ShowProgressBars;
        HeaderToggle.IsChecked = _settings.ShowWidgetHeader;
        OpacitySlider.Value = _settings.WidgetOpacity * 100;
        StartupToggle.IsChecked = StartupStateProvider?.Invoke() ?? false;
        UpdateToggle.IsChecked = _settings.CheckForUpdatesOnStartup;
        UpdateAccentSelection();
        var currentVersion = VelopackUpdateService.CurrentVersion;
        CurrentVersionText.Text = currentVersion;
        UpdateChannelText.Text = currentVersion.Contains('-', StringComparison.Ordinal) ? "릴리스 후보 채널" : "안정 채널";
        AboutVersionText.Text = $"버전 {currentVersion}";
        SetUpdateCheckResult("업데이트 확인 버튼을 눌러 현재 상태를 확인하세요.");
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

    internal void SetCodexLoginPending(bool pending)
    {
        CodexConnectionButton.IsEnabled = !pending;
        if (pending) CodexConnectionButton.Content = "브라우저에서 로그인";
        else UpdateCodexConnectionUi();
    }

    private void UpdateCodexConnectionUi()
    {
        if (CodexConnectionTitle is null) return;
        var executable = CodexUsageClient.FindExecutable();
        var state = _applicationState;
        if (state?.CodexStatus == UsageStatus.Ready && state.CodexSnapshot is not null)
        {
            CodexConnectionTitle.Text = "Codex 사용량 연결됨";
            CodexConnectionDescription.Text = "사용률, 초기화 시각과 초기화권을 공식 로컬 app-server에서 확인합니다.";
            CodexConnectionButton.Visibility = Visibility.Collapsed;
        }
        else if (executable is not null)
        {
            CodexConnectionTitle.Text = CodexUsageClient.IsDesktopBundledExecutable(executable)
                ? "Codex Desktop 감지됨 · 로그인 필요" : "Codex 로그인 필요";
            CodexConnectionDescription.Text = "CLI를 직접 사용하지 않아도 ChatGPT 로그인으로 Codex 사용량을 연결할 수 있어요.";
            CodexConnectionButton.Content = "Codex 로그인";
            CodexConnectionButton.Visibility = Visibility.Visible;
        }
        else
        {
            CodexConnectionTitle.Text = CodexUsageClient.IsDesktopInstalled
                ? "Codex Desktop 업데이트 필요" : "Codex 설치 필요";
            CodexConnectionDescription.Text = CodexUsageClient.IsDesktopInstalled
                ? "호환되는 로컬 런타임을 찾지 못했습니다. Codex Desktop을 업데이트해 주세요."
                : "Codex Desktop 또는 CLI를 설치하면 dejavu가 자동으로 감지합니다.";
            CodexConnectionButton.Content = "Codex 설치";
            CodexConnectionButton.Visibility = Visibility.Visible;
        }
    }

    private void UpdateClaudeConnectionUi()
    {
        if (ClaudeConnectionTitle is null) return;
        var state = _applicationState;
        if (state?.ClaudeStatus == UsageStatus.Ready && state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode)
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
        else if (state?.ClaudeStatus == UsageStatus.Loading)
        {
            ClaudeConnectionTitle.Text = "Claude 연결 확인 중";
            ClaudeConnectionDescription.Text = "로컬 Claude Code 로그인과 Desktop 사용 기록을 확인합니다.";
            ClaudeConnectionButton.Visibility = Visibility.Collapsed;
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

    private static Choice<T>? Find<T>(ItemsControl control, T value) where T : notnull =>
        control.Items.Cast<Choice<T>>().FirstOrDefault(item => EqualityComparer<T>.Default.Equals(item.Value, value));

    private void SaveAndNotify(bool applyTheme = false)
    {
        _settings.Save();
        if (applyTheme) ThemeManager.Apply(_settings);
        UpdateStatusLabels();
        SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void UpdateStatusLabels()
    {
        BarsStatus.Text = _settings.ShowProgressBars ? "켜짐" : "꺼짐";
        HeaderToggleStatus.Text = _settings.ShowWidgetHeader ? "켜짐" : "꺼짐";
        StartupStatus.Text = StartupToggle.IsChecked == true ? "켜짐" : "꺼짐";
        UpdateToggleStatus.Text = _settings.CheckForUpdatesOnStartup ? "켜짐" : "꺼짐";
        OpacityValue.Text = $"{OpacitySlider.Value:0}%";
    }

    private void OnNavigationChanged(object sender, RoutedEventArgs e)
    {
        if (AppearancePanel is null) return;
        AppearancePanel.Visibility = AppearanceNav.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
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
        _settings.ShowWidgetHeader = HeaderToggle.IsChecked == true;
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

    private void OnStartupChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        UpdateStatusLabels();
        StartupChanged?.Invoke(this, StartupToggle.IsChecked == true);
    }

    private void OnUpdateToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _settings.CheckForUpdatesOnStartup = UpdateToggle.IsChecked == true;
        SaveAndNotify();
    }

    internal void SetUpdateCheckLoading()
    {
        UpdateCheckProgress.Visibility = Visibility.Visible;
        UpdateCheckStatus.Text = "새 버전을 확인하는 중입니다…";
        CheckUpdatesButton.Content = "확인 중";
        CheckUpdatesButton.Tag = null;
        CheckUpdatesButton.IsEnabled = false;
    }

    internal void SetUpdateCheckResult(string message, bool updateAvailable = false)
    {
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
        _settings.ShowWidgetHeader = true;
        _settings.RefreshSeconds = 60;
        _settings.TrayIconStyle = TrayIconStyle.ClaudeMark;
        _settings.WidgetDensity = WidgetDensity.Compact;
        _settings.WidgetLayout = WidgetLayout.SingleRow;
        _settings.ServiceDisplayMode = ServiceDisplayMode.AutoDetect;
        _settings.WidgetPlacement = WidgetPlacement.TaskbarRight;
        _settings.Theme = ThemePreference.System;
        _settings.CheckForUpdatesOnStartup = true;
        _settings.WidgetLeft = null;
        _settings.WidgetTop = null;
        SaveAndNotify(applyTheme: true);
        LoadValues();
        PositionResetRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnOpenDiagnostics(object sender, RoutedEventArgs e)
    {
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");
        Directory.CreateDirectory(directory);
        Process.Start(new ProcessStartInfo("explorer.exe", directory) { UseShellExecute = true });
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    private sealed record Choice<T>(T Value, string Label)
    {
        public override string ToString() => Label;
    }
}
