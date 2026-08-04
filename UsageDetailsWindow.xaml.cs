using System.Windows;
using System.Windows.Media;
using Forms = System.Windows.Forms;
using MediaBrushes = System.Windows.Media.Brushes;

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
        ApplyThemeStructure(settings.WidgetTheme);
        var progressStyle = FindResource(ThemeManager.WidgetProgressStyleKey(settings.WidgetTheme))
            as System.Windows.Style;
        foreach (var bar in new[]
                 {
                     FiveHourBar, WeeklyBar, FableBar, CodexFiveHourBar, CodexWeeklyBar
                 })
            bar.Style = progressStyle;
        var (showClaude, showCodex) = settings.ResolveServices(state);
        ClaudeCard.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CodexCard.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        ServiceDivider.Visibility = showClaude && showCodex &&
                                    settings.WidgetTheme is not (WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit)
            ? Visibility.Visible : Visibility.Collapsed;
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

    private void ApplyThemeStructure(WidgetVisualTheme theme)
    {
        DetailsCard.Padding = new Thickness(18);
        DetailsHeader.Padding = new Thickness(0, 0, 0, 14);
        DetailsHeader.BorderThickness = new Thickness(0, 0, 0, 1);
        DetailsBody.Margin = new Thickness(0, 14, 0, 12);
        DetailsFooter.Padding = new Thickness(0, 12, 0, 0);
        DetailsFooter.BorderThickness = new Thickness(0, 1, 0, 0);
        DetailsThemeBadge.Width = DetailsThemeBadge.Height = 34;
        DetailsThemeBadge.CornerRadius = ResourceCornerRadius("BadgeCornerRadius");
        DetailsThemeBadge.BorderThickness = new Thickness(1);
        ServiceDivider.Height = 1;
        ServiceDivider.Margin = new Thickness(0, 18, 0, 14);

        ResetSectionCard(ClaudeCard);
        ResetSectionCard(CodexCard);
        ResetSectionCard(CreditsCard, new Thickness(12, 9, 12, 9));
        ResetMetricRows();

        DetailsBrandText.Text = "dejavu";
        ClaudeSectionTitle.Text = "Claude";
        CodexSectionTitle.Text = "Codex";

        switch (theme)
        {
            case WidgetVisualTheme.RetroNight:
                DetailsCard.Padding = new Thickness(12);
                DetailsHeader.Padding = new Thickness(0, 0, 0, 10);
                DetailsBody.Margin = new Thickness(0, 10, 0, 10);
                DetailsThemeBadge.Width = DetailsThemeBadge.Height = 30;
                DetailsThemeBadge.CornerRadius = new CornerRadius(0);
                DetailsBrandText.Text = "DEJAVU // STATUS";
                ClaudeSectionTitle.Text = "CLAUDE STATUS";
                CodexSectionTitle.Text = "CODEX STATUS";
                ConfigureSectionCard(ClaudeCard, 0, new Thickness(10), new Thickness(0), "SurfaceBrush");
                ConfigureSectionCard(CodexCard, 0, new Thickness(10), new Thickness(0), "SurfaceBrush");
                ConfigureSectionCard(CreditsCard, 0, new Thickness(10, 8, 10, 8), new Thickness(0), "RaisedSurfaceBrush");
                StyleRowsAsCells(new Thickness(7, 5, 7, 5), 1);
                ServiceDivider.Height = 2;
                ServiceDivider.Margin = new Thickness(0, 8, 0, 8);
                break;

            case WidgetVisualTheme.FluentGlass:
                DetailsCard.Padding = new Thickness(16);
                DetailsHeader.BorderThickness = new Thickness(0);
                DetailsBody.Margin = new Thickness(0, 10, 0, 10);
                DetailsFooter.BorderThickness = new Thickness(0);
                DetailsThemeBadge.Width = DetailsThemeBadge.Height = 38;
                DetailsBrandText.Text = "dejavu glass";
                ConfigureSectionCard(ClaudeCard, 16, new Thickness(14), new Thickness(0, 0, 0, 10), "RaisedSurfaceBrush");
                ConfigureSectionCard(CodexCard, 16, new Thickness(14), new Thickness(0), "RaisedSurfaceBrush");
                ConfigureSectionCard(CreditsCard, 12, new Thickness(12, 9, 12, 9), new Thickness(0), "SurfaceBrush");
                ServiceDivider.Visibility = Visibility.Collapsed;
                break;

            case WidgetVisualTheme.TerminalMono:
                DetailsCard.Padding = new Thickness(10);
                DetailsHeader.Padding = new Thickness(8, 7, 8, 8);
                DetailsHeader.BorderThickness = new Thickness(1);
                DetailsBody.Margin = new Thickness(0, 8, 0, 8);
                DetailsFooter.Padding = new Thickness(8, 8, 8, 0);
                DetailsThemeBadge.Width = 42;
                DetailsThemeBadge.Height = 28;
                DetailsThemeBadge.CornerRadius = new CornerRadius(0);
                DetailsBrandText.Text = "dejavu.status";
                ClaudeSectionTitle.Text = "[CLAUDE]";
                CodexSectionTitle.Text = "[CODEX]";
                ConfigureSectionCard(ClaudeCard, 0, new Thickness(10), new Thickness(0), "SurfaceBrush");
                ConfigureSectionCard(CodexCard, 0, new Thickness(10), new Thickness(0), "SurfaceBrush");
                ConfigureSectionCard(CreditsCard, 0, new Thickness(10, 8, 10, 8), new Thickness(0), "RaisedSurfaceBrush");
                StyleRowsAsCells(new Thickness(8, 6, 8, 6), 1);
                ServiceDivider.Height = 1;
                ServiceDivider.Margin = new Thickness(0, 7, 0, 7);
                break;

            case WidgetVisualTheme.Orbit:
                DetailsCard.Padding = new Thickness(16);
                DetailsHeader.Padding = new Thickness(2, 0, 2, 16);
                DetailsHeader.BorderThickness = new Thickness(0);
                DetailsBody.Margin = new Thickness(0, 6, 0, 10);
                DetailsThemeBadge.Width = DetailsThemeBadge.Height = 42;
                DetailsThemeBadge.CornerRadius = new CornerRadius(21);
                DetailsBrandText.Text = "DEJAVU ORBIT";
                ClaudeSectionTitle.Text = "CLAUDE CLUSTER";
                CodexSectionTitle.Text = "CODEX CLUSTER";
                ConfigureSectionCard(ClaudeCard, 18, new Thickness(16), new Thickness(0, 0, 0, 12), "RaisedSurfaceBrush");
                ConfigureSectionCard(CodexCard, 18, new Thickness(16), new Thickness(0), "RaisedSurfaceBrush");
                ConfigureSectionCard(CreditsCard, 14, new Thickness(12, 10, 12, 10), new Thickness(0), "SurfaceBrush");
                ServiceDivider.Visibility = Visibility.Collapsed;
                break;

            case WidgetVisualTheme.PaperInk:
                DetailsCard.Padding = new Thickness(20, 18, 20, 16);
                DetailsHeader.Padding = new Thickness(0, 0, 0, 12);
                DetailsBody.Margin = new Thickness(0, 12, 0, 10);
                DetailsThemeBadge.Width = 26;
                DetailsThemeBadge.Height = 34;
                DetailsThemeBadge.CornerRadius = new CornerRadius(0);
                DetailsThemeBadge.BorderThickness = new Thickness(0, 0, 1, 0);
                DetailsBrandText.Text = "dejavu 사용 기록";
                ClaudeSectionTitle.Text = "I. CLAUDE";
                CodexSectionTitle.Text = "II. CODEX";
                ConfigureSectionCard(ClaudeCard, 0, new Thickness(0, 2, 0, 8), new Thickness(0), null,
                    new Thickness(2, 0, 0, 0));
                ConfigureSectionCard(CodexCard, 0, new Thickness(0, 2, 0, 8), new Thickness(0), null,
                    new Thickness(2, 0, 0, 0));
                ConfigureSectionCard(CreditsCard, 0, new Thickness(10, 8, 10, 8), new Thickness(0), null,
                    new Thickness(0, 1, 0, 1));
                StyleRowsAsLedger();
                ServiceDivider.Height = 1;
                ServiceDivider.Margin = new Thickness(0, 12, 0, 12);
                break;
        }
    }

    private void ResetMetricRows()
    {
        foreach (var row in MetricRows())
        {
            row.Background = MediaBrushes.Transparent;
            row.Opacity = 1;
            row.Margin = row == ClaudeFiveRow || row == ClaudeWeeklyRow || row == CodexFiveRow
                ? new Thickness(0, 0, 0, 14)
                : row == CodexWeeklyRow ? new Thickness(0, 0, 0, 12) : new Thickness(0);
        }
    }

    private void StyleRowsAsCells(Thickness paddingApproximation, double opacity)
    {
        foreach (var row in MetricRows())
        {
            row.SetResourceReference(System.Windows.Controls.Panel.BackgroundProperty, "RaisedSurfaceBrush");
            row.Opacity = opacity;
            row.Margin = new Thickness(0, 0, 0, paddingApproximation.Bottom + 3);
        }
    }

    private void StyleRowsAsLedger()
    {
        foreach (var row in MetricRows())
        {
            row.Background = MediaBrushes.Transparent;
            row.Margin = new Thickness(8, 0, 0, 13);
        }
    }

    private System.Windows.Controls.Grid[] MetricRows() =>
        [ClaudeFiveRow, ClaudeWeeklyRow, ClaudeFableRow, CodexFiveRow, CodexWeeklyRow];

    private void ResetSectionCard(System.Windows.Controls.Border border, Thickness? padding = null)
    {
        border.Background = MediaBrushes.Transparent;
        border.BorderBrush = ResourceBrush("BorderBrush");
        border.BorderThickness = new Thickness(0);
        border.CornerRadius = new CornerRadius(0);
        border.Padding = padding ?? new Thickness(0);
        border.Margin = new Thickness(0);
    }

    private void ConfigureSectionCard(System.Windows.Controls.Border border, double radius, Thickness padding,
        Thickness margin, string? backgroundResource, Thickness? borderThickness = null)
    {
        border.CornerRadius = new CornerRadius(radius);
        border.Padding = padding;
        border.Margin = margin;
        border.BorderBrush = ResourceBrush("BorderBrush");
        border.BorderThickness = borderThickness ?? new Thickness(1);
        if (backgroundResource is null) border.Background = MediaBrushes.Transparent;
        else border.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, backgroundResource);
    }

    private System.Windows.Media.Brush ResourceBrush(string key) =>
        FindResource(key) as System.Windows.Media.Brush ?? MediaBrushes.Transparent;
    private CornerRadius ResourceCornerRadius(string key) =>
        FindResource(key) is CornerRadius radius ? radius : new CornerRadius(0);

    internal void ShowNear(UsageWidgetWindow widget)
    {
        var widgetCenter = new System.Drawing.Point(
            (int)Math.Round(widget.Left + widget.Width / 2),
            (int)Math.Round(widget.Top + widget.Height / 2));
        var work = Forms.Screen.FromPoint(widgetCenter).WorkingArea;
        Left = Math.Clamp(widget.Left + widget.Width - Width, work.Left + 8, Math.Max(work.Left + 8, work.Right - Width - 8));
        // A WPF Window cannot be measured safely before its native HWND exists.
        // .NET 10 treats that path as an invariant violation and terminates the
        // process with FailFast, so show it at a safe provisional position first.
        Top = Math.Clamp(widget.Top + widget.Height + 8, work.Top + 8,
            Math.Max(work.Top + 8, work.Bottom - MinHeight - 8));
        if (!IsVisible) Show();
        UpdateLayout();
        var popupHeight = Math.Max(MinHeight, ActualHeight);
        var above = widget.Top - popupHeight - 8;
        var below = widget.Top + widget.Height + 8;
        Top = above >= work.Top + 8
            ? above
            : Math.Clamp(below, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - popupHeight - 8));
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
