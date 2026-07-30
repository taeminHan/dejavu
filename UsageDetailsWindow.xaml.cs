using System.Windows;
using System.Windows.Media;

namespace ClaudeUsageTray;

public partial class UsageDetailsWindow : Window
{
    internal UsageDetailsWindow() => InitializeComponent();

    internal event EventHandler? RefreshRequested;
    internal event EventHandler? SettingsRequested;
    internal event EventHandler? LoginRequested;
    private bool _loginAction;

    internal void UpdateState(ApplicationState state, TraySettings settings)
    {
        var (showClaude, showCodex) = settings.ResolveServices(state);
        ClaudeSection.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CodexSection.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        ServiceDivider.Visibility = showClaude && showCodex ? Visibility.Visible : Visibility.Collapsed;
        Height = showClaude && showCodex ? 470 : showClaude ? 350 : showCodex ? 330 : 220;
        StatusText.Text = showClaude && showCodex ? state.Message
            : showClaude ? state.ClaudeMessage
            : showCodex ? state.CodexMessage
            : "사용 가능한 서비스를 찾지 못했습니다";
        FooterText.Text = state.RetryAt is not null
            ? $"{state.RetryAt.Value.LocalDateTime:HH:mm}에 자동 재시도"
            : state.UpdatedAt is not null ? $"마지막 확인 {state.UpdatedAt.Value.LocalDateTime:HH:mm:ss}" : "아직 확인된 값이 없습니다";
        _loginAction = showClaude && state.ClaudeStatus == UsageStatus.LoginRequired;
        ActionButton.Content = _loginAction ? "Claude 로그인 열기" : "지금 새로고침";
        ClaudeStatusText.Text = state.ClaudeMessage;
        CodexStatusText.Text = state.CodexMessage;
        SetMetric(FiveHourValue, FiveHourBar, FiveHourReset, state.Snapshot?.FiveHour, settings);
        SetMetric(WeeklyValue, WeeklyBar, WeeklyReset, state.Snapshot?.Weekly, settings);
        SetMetric(FableValue, FableBar, FableReset, state.Snapshot?.Fable, settings);
        SetMetric(CodexFiveHourValue, CodexFiveHourBar, CodexFiveHourReset, state.CodexSnapshot?.FiveHour, settings);
        SetMetric(CodexWeeklyValue, CodexWeeklyBar, CodexWeeklyReset, state.CodexSnapshot?.Weekly, settings);
        CodexResetCredits.Text = state.CodexSnapshot?.ResetCredits is int credits ? $"{credits}개" : "--개";
        CodexResetExpiry.Text = state.CodexSnapshot?.ResetCreditsExpireAt is DateTimeOffset expiry
            ? $"가장 빠른 만료 {expiry.LocalDateTime:M월 d일 HH:mm}" : "읽기 전용";
    }

    internal void ShowNear(UsageWidgetWindow widget)
    {
        Left = Math.Max(SystemParameters.VirtualScreenLeft + 8, widget.Left + widget.Width - Width);
        Top = widget.Top > Height + 16 ? widget.Top - Height - 8 : widget.Top + widget.Height + 8;
        Show();
        Activate();
    }

    private void SetMetric(System.Windows.Controls.TextBlock valueLabel, System.Windows.Controls.ProgressBar bar,
        System.Windows.Controls.TextBlock resetLabel, UsageLimit? limit, TraySettings settings)
    {
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        valueLabel.Text = value is null ? "--%" : $"{value:0}%";
        bar.Value = value ?? 0;
        bar.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
        resetLabel.Text = limit?.ResetsAt is null ? "" : $"초기화 {limit.ResetsAt.Value.LocalDateTime:ddd HH:mm}";
        var key = settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : settings.UseThresholdColors && value >= 70 ? "WarningBrush" : "AccentBrush";
        valueLabel.Foreground = FindResource(key) as System.Windows.Media.Brush;
        bar.Foreground = FindResource(key) as System.Windows.Media.Brush;
    }

    private void OnActionClick(object sender, RoutedEventArgs e)
    {
        if (_loginAction) LoginRequested?.Invoke(this, EventArgs.Empty);
        else RefreshRequested?.Invoke(this, EventArgs.Empty);
    }
    private void OnSettingsClick(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnDeactivated(object? sender, EventArgs e) => Hide();
}
