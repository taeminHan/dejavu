using System.Windows;
using System.Windows.Controls;

namespace ClaudeUsageTray;

public partial class OnboardingWindow : Window
{
    private readonly TraySettings _settings;

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
    internal event EventHandler? LoginRequested;

    internal void RefreshDetection() => UpdateCredentialState();

    private void UpdateCredentialState()
    {
        var environment = ClaudeEnvironmentDetector.Detect();
        var codexInstalled = CodexUsageClient.FindExecutable() is not null;
        TitleText.Text = environment.IsLoggedIn || codexInstalled
            ? "사용 가능한 서비스를 확인했어요" : "연결된 서비스를 찾지 못했어요";
        ClaudeCredentialTitle.Text = environment.IsLoggedIn ? "Claude Code 로그인 감지됨"
            : environment.IsInstalled ? "Claude Code 설치됨 · 로그인 필요" : "Claude Code를 찾지 못했습니다";
        ClaudeCredentialDescription.Text = environment.IsLoggedIn
            ? "사용량 요청은 Anthropic으로 직접 전송되며 dejavu 서버를 거치지 않습니다"
            : environment.IsInstalled
                ? "로그인 창을 열면 완료 상태를 자동으로 감지합니다"
                : "설치 안내를 연 뒤 dejavu가 자동으로 다시 확인합니다";
        ClaudeCredentialDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty,
            environment.IsLoggedIn ? "AccentBrush" : "WarningBrush");
        CodexCredentialTitle.Text = codexInstalled ? "Codex CLI 감지됨" : "Codex CLI를 찾지 못했습니다";
        CodexCredentialDescription.Text = codexInstalled
            ? "로그인 상태와 사용량은 공식 로컬 app-server에서 확인합니다"
            : "Codex를 사용하지 않는다면 설치하지 않아도 됩니다";
        CodexCredentialDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty,
            codexInstalled ? "AccentBrush" : "WarningBrush");
        LoginButton.Content = environment.IsInstalled ? "Claude 로그인 열기" : "설치 안내 열기";
        LoginButton.Visibility = environment.IsLoggedIn ? Visibility.Collapsed : Visibility.Visible;
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
    private void OnLoginClick(object sender, RoutedEventArgs e) => LoginRequested?.Invoke(this, EventArgs.Empty);

    private sealed record PlacementChoice(WidgetPlacement Value, string Label)
    {
        public override string ToString() => Label;
    }

    private sealed record ServiceChoice(ServiceDisplayMode Value, string Label)
    {
        public override string ToString() => Label;
    }
}
