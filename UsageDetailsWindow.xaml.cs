using System.Windows;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace ClaudeUsageTray;

public partial class UsageDetailsWindow : Window
{
    internal UsageDetailsWindow() => InitializeComponent();

    internal event EventHandler? RefreshRequested;
    internal event EventHandler? SettingsRequested;
    internal event EventHandler? ClaudeLoginRequested;
    internal event EventHandler? CodexLoginRequested;
    private DetailsAction _action;

    internal void UpdateState(ApplicationState state, TraySettings settings)
    {
        var (showClaude, showCodex) = settings.ResolveServices(state);
        ClaudeSection.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CodexSection.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        ServiceDivider.Visibility = showClaude && showCodex ? Visibility.Visible : Visibility.Collapsed;
        StatusText.Text = showClaude && showCodex ? state.Message
            : showClaude ? state.ClaudeMessage
            : showCodex ? state.CodexMessage
            : "사용 가능한 서비스를 찾지 못했습니다";
        FooterText.Text = state.RetryAt is not null
            ? $"{state.RetryAt.Value.LocalDateTime:HH:mm}에 자동 재시도"
            : state.UpdatedAt is not null ? $"마지막 확인 {state.UpdatedAt.Value.LocalDateTime:HH:mm:ss}" : "아직 확인된 값이 없습니다";
        _action = showClaude && state.ClaudeStatus == UsageStatus.LoginRequired
            ? DetailsAction.ClaudeLogin
            : showCodex && state.CodexStatus == UsageStatus.LoginRequired
                ? DetailsAction.CodexLogin : DetailsAction.Refresh;
        ActionButton.Content = _action switch
        {
            DetailsAction.ClaudeLogin => "Claude Code 로그인",
            DetailsAction.CodexLogin => "Codex 로그인",
            _ => "지금 새로고침"
        };
        ClaudeStatusText.Text = state.ClaudeMessage;
        CodexStatusText.Text = state.CodexMessage;
        SetMetric(FiveHourValue, FiveHourBar, FiveHourReset, state.Snapshot?.FiveHour, settings);
        SetMetric(WeeklyValue, WeeklyBar, WeeklyReset, state.Snapshot?.Weekly, settings);
        SetMetric(FableValue, FableBar, FableReset, state.Snapshot?.Fable, settings);
        if (state.Snapshot?.Source == ClaudeUsageSource.ClaudeDesktop && state.Snapshot.Fable is null)
        {
            FableValue.Text = "미제공";
            FableReset.Text = "Fable 확인에는 Claude Code 로그인 필요";
        }
        else if (state.Snapshot?.Source == ClaudeUsageSource.ClaudeCode && state.Snapshot.Fable is null)
        {
            FableValue.Text = "미제공";
            FableReset.Text = "현재 계정에 Fable 전용 한도 없음";
        }
        SetMetric(CodexFiveHourValue, CodexFiveHourBar, CodexFiveHourReset, state.CodexSnapshot?.FiveHour, settings);
        SetMetric(CodexWeeklyValue, CodexWeeklyBar, CodexWeeklyReset, state.CodexSnapshot?.Weekly, settings);
        CodexResetCredits.Text = state.CodexSnapshot?.ResetCredits is int credits ? $"{credits}개" : "--개";
        CodexResetExpiry.Text = state.CodexSnapshot?.ResetCreditsExpireAt is DateTimeOffset expiry
            ? $"가장 빠른 만료 {expiry.LocalDateTime:M월 d일 HH:mm}" : "읽기 전용";
    }

    internal void ShowNear(UsageWidgetWindow widget)
    {
        Measure(new System.Windows.Size(Width, double.PositiveInfinity));
        var popupHeight = Math.Max(MinHeight, DesiredSize.Height);
        var widgetCenter = new System.Drawing.Point(
            (int)Math.Round(widget.Left + widget.Width / 2),
            (int)Math.Round(widget.Top + widget.Height / 2));
        var work = Forms.Screen.FromPoint(widgetCenter).WorkingArea;
        Left = Math.Clamp(widget.Left + widget.Width - Width, work.Left + 8, Math.Max(work.Left + 8, work.Right - Width - 8));
        var above = widget.Top - popupHeight - 8;
        var below = widget.Top + widget.Height + 8;
        Top = above >= work.Top + 8
            ? above
            : Math.Clamp(below, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - popupHeight - 8));
        Show();
        UpdateLayout();
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
        if (_action == DetailsAction.ClaudeLogin) ClaudeLoginRequested?.Invoke(this, EventArgs.Empty);
        else if (_action == DetailsAction.CodexLogin) CodexLoginRequested?.Invoke(this, EventArgs.Empty);
        else RefreshRequested?.Invoke(this, EventArgs.Empty);
    }
    private void OnSettingsClick(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnDeactivated(object? sender, EventArgs e) => Hide();

    private enum DetailsAction { Refresh, ClaudeLogin, CodexLogin }
}
