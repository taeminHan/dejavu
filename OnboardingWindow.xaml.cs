using System.Windows;
using System.Windows.Controls;

namespace ClaudeUsageTray;

public partial class OnboardingWindow : Window
{
    private readonly TraySettings _settings;
    private bool _loginRequiresClaudeCode = true;
    private ApplicationState? _applicationState;

    internal OnboardingWindow(TraySettings settings)
    {
        InitializeComponent();
        _settings = settings;
        PlacementCombo.ItemsSource = new[]
        {
            new PlacementChoice(WidgetPlacement.TaskbarRight, "작업표시줄 위 · 오른쪽"),
            new PlacementChoice(WidgetPlacement.TopRight, "화면 오른쪽 위"),
            new PlacementChoice(WidgetPlacement.Custom, "직접 배치")
        };
        ServiceCombo.ItemsSource = new[]
        {
            new ServiceChoice(ServiceDisplayMode.AutoDetect, "자동 감지"),
            new ServiceChoice(ServiceDisplayMode.ClaudeAndCodex, "Claude + Codex"),
            new ServiceChoice(ServiceDisplayMode.ClaudeOnly, "Claude만"),
            new ServiceChoice(ServiceDisplayMode.CodexOnly, "Codex만")
        };
        ServiceCombo.SelectedIndex = settings.ServiceDisplayMode switch
        {
            ServiceDisplayMode.ClaudeAndCodex => 1,
            ServiceDisplayMode.ClaudeOnly => 2,
            ServiceDisplayMode.CodexOnly => 3,
            _ => 0
        };
        PlacementCombo.SelectedIndex = settings.WidgetPlacement switch
        {
            WidgetPlacement.TopRight => 1,
            WidgetPlacement.Custom => 2,
            _ => 0
        };
        UpdateCredentialState();
    }

    internal event EventHandler? Completed;
    internal event EventHandler? PrivacyRequested;
    internal event Action<bool>? LoginRequested;
    internal event EventHandler? CodexLoginRequested;

    internal void RefreshDetection() => UpdateCredentialState();

    internal void SetCodexLoginPending(bool pending)
    {
        CodexLoginButton.IsEnabled = !pending;
        if (pending) CodexLoginButton.Content = "브라우저에서 로그인";
        else UpdateCredentialState();
    }

    internal void UpdateState(ApplicationState state)
    {
        _applicationState = state;
        UpdateCredentialState();
    }

    private void UpdateCredentialState()
    {
        var environment = ClaudeEnvironmentDetector.Detect();
        var fullUsageAvailable = _applicationState?.ClaudeStatus == UsageStatus.Ready &&
                                 _applicationState.Snapshot?.Source == ClaudeUsageSource.ClaudeCode;
        var desktopUsageAvailable = _applicationState?.ClaudeStatus == UsageStatus.Ready &&
                                    _applicationState.Snapshot?.Source == ClaudeUsageSource.ClaudeDesktop ||
                                    ClaudeDesktopUsageReader.HasRecentUsage();
        var claudeAvailable = fullUsageAvailable || desktopUsageAvailable ||
                              _applicationState is null && environment.IsLoggedIn;
        var codexExecutable = CodexUsageClient.FindExecutable();
        var codexRuntimeAvailable = codexExecutable is not null;
        var codexReady = _applicationState?.CodexStatus == UsageStatus.Ready &&
                         _applicationState.CodexSnapshot is not null;
        TitleText.Text = claudeAvailable || codexReady || codexRuntimeAvailable
            ? "사용 가능한 서비스를 확인했어요" : "연결된 서비스를 찾지 못했어요";
        ClaudeCredentialTitle.Text = fullUsageAvailable ? "Claude Code 연결됨"
            : desktopUsageAvailable ? "Claude Desktop 사용량 감지됨"
            : environment.IsLoggedIn ? "Claude Code 로그인 확인 중"
            : environment.IsInstalled ? "Claude Code 설치됨 · 로그인 필요"
            : ClaudeDesktopUsageReader.IsInstalled ? "Claude Desktop 설치됨 · 최근 사용 기록 없음"
            : "Claude를 찾지 못했습니다";
        ClaudeCredentialDescription.Text = fullUsageAvailable
            ? "5시간·주간과 계정에 제공되는 Fable 한도를 확인합니다"
            : desktopUsageAvailable
                ? environment.IsInstalled
                    ? "Fable 사용량을 확인하기 위해서는 Claude Code 로그인이 필요해요."
                    : "Fable 사용량을 확인하려면 Claude Code 설치와 로그인이 필요해요."
            : environment.IsInstalled
                ? "로그인 창을 열면 완료 상태를 자동으로 감지합니다"
                : ClaudeDesktopUsageReader.IsInstalled
                    ? "Claude Desktop을 열어 사용하면 자동으로 다시 확인합니다"
                    : "설치 안내를 연 뒤 dejavu가 자동으로 다시 확인합니다";
        ClaudeCredentialDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty,
            claudeAvailable ? "AccentBrush" : "WarningBrush");
        CodexCredentialTitle.Text = codexReady ? "Codex 사용량 연결됨"
            : codexRuntimeAvailable && CodexUsageClient.IsDesktopBundledExecutable(codexExecutable)
                ? "Codex Desktop 감지됨 · 로그인 필요"
            : codexRuntimeAvailable ? "Codex 감지됨 · 로그인 필요"
            : CodexUsageClient.IsDesktopInstalled ? "Codex Desktop 업데이트 필요"
            : "Codex를 찾지 못했습니다";
        CodexCredentialDescription.Text = codexReady
            ? "사용량과 초기화권을 공식 로컬 app-server에서 확인합니다"
            : codexRuntimeAvailable
                ? "CLI를 따로 사용하지 않아도 ChatGPT 로그인으로 Codex 사용량을 연결할 수 있어요."
                : CodexUsageClient.IsDesktopInstalled
                    ? "호환되는 Codex 런타임을 찾지 못했습니다. Desktop 앱을 업데이트해 주세요."
                    : "Codex Desktop 또는 CLI를 설치하면 자동으로 감지합니다.";
        CodexCredentialDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty,
            codexReady ? "AccentBrush" : "WarningBrush");
        CodexLoginButton.Content = codexRuntimeAvailable ? "Codex 로그인" : "Codex 설치";
        CodexLoginButton.Visibility = codexReady ? Visibility.Collapsed : Visibility.Visible;
        _loginRequiresClaudeCode = environment.IsInstalled || desktopUsageAvailable || !ClaudeDesktopUsageReader.IsInstalled;
        LoginButton.Content = desktopUsageAvailable ? environment.IsInstalled ? "Claude Code 로그인" : "Claude Code 설치"
            : environment.IsInstalled ? "Claude Code 로그인"
            : ClaudeDesktopUsageReader.IsInstalled ? "Claude Desktop 열기" : "설치 안내 열기";
        LoginButton.Visibility = fullUsageAvailable ? Visibility.Collapsed : Visibility.Visible;
    }

    private void OnPlacementChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PlacementCombo.SelectedItem is PlacementChoice choice)
            _settings.WidgetPlacement = choice.Value;
    }

    private void OnServiceChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ServiceCombo.SelectedItem is ServiceChoice choice)
            _settings.ServiceDisplayMode = choice.Value;
    }

    private void OnContinueClick(object sender, RoutedEventArgs e)
    {
        _settings.FirstRunCompleted = true;
        _settings.Save();
        Hide();
        Completed?.Invoke(this, EventArgs.Empty);
    }

    private void OnPrivacyClick(object sender, RoutedEventArgs e) => PrivacyRequested?.Invoke(this, EventArgs.Empty);
    private void OnLoginClick(object sender, RoutedEventArgs e) => LoginRequested?.Invoke(_loginRequiresClaudeCode);
    private void OnCodexLoginClick(object sender, RoutedEventArgs e) =>
        CodexLoginRequested?.Invoke(this, EventArgs.Empty);

    private sealed record PlacementChoice(WidgetPlacement Value, string Label)
    {
        public override string ToString() => Label;
    }

    private sealed record ServiceChoice(ServiceDisplayMode Value, string Label)
    {
        public override string ToString() => Label;
    }
}
