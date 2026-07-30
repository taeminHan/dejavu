using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace ClaudeUsageTray;

public partial class UsageWidgetWindow : Window
{
    private ApplicationState _state = ApplicationState.Loading();
    private TraySettings _settings;

    internal UsageWidgetWindow(TraySettings settings)
    {
        InitializeComponent();
        _settings = settings;
        ApplySettings(settings);
    }

    internal event EventHandler? WidgetClicked;
    internal event EventHandler? SettingsRequested;
    internal event EventHandler? PositionChangedByUser;

    internal void ApplySettings(TraySettings settings)
    {
        _settings = settings;
        Opacity = settings.WidgetOpacity;
        var compact = settings.WidgetDensity == WidgetDensity.Compact;
        var singleRow = settings.WidgetLayout == WidgetLayout.SingleRow;
        CompactPanel.Visibility = singleRow ? Visibility.Visible : Visibility.Collapsed;
        ComfortablePanel.Visibility = singleRow ? Visibility.Collapsed : Visibility.Visible;
        CompactStatusDot.Visibility = settings.ShowWidgetHeader ? Visibility.Visible : Visibility.Collapsed;
        CompactStatusColumn.Width = new GridLength(settings.ShowWidgetHeader ? 14 : 0);
        HeaderPanel.Visibility = settings.ShowWidgetHeader ? Visibility.Visible : Visibility.Collapsed;
        HeaderRow.Height = new GridLength(settings.ShowWidgetHeader ? 18 : 0);
        WidgetCard.Padding = compact ? new Thickness(10, 8, 10, 8) : new Thickness(14, 11, 14, 11);
        WidgetCard.CornerRadius = new CornerRadius(compact ? 11 : 14);
        foreach (var bar in new[] { FiveHourBar, WeeklyBar, FableBar, CodexBar, CompactFiveHourBar, CompactWeeklyBar, CompactFableBar, CompactCodexBar })
            bar.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
        UpdateState(_state);
    }

    internal void UpdateState(ApplicationState state)
    {
        _state = state;
        HeaderStatus.Text = state.Status switch
        {
            UsageStatus.Ready => state.UpdatedAt is null ? "업데이트됨" : $"{state.UpdatedAt.Value.LocalDateTime:HH:mm} 업데이트",
            UsageStatus.Loading => "새로고침 중",
            UsageStatus.RateLimited => "자동 재시도",
            UsageStatus.LoginRequired => "로그인 필요",
            UsageStatus.Offline => "오프라인",
            _ => "확인 필요"
        };

        var statusBrush = FindResource(state.Status switch
        {
            UsageStatus.Ready or UsageStatus.Loading => "AccentBrush",
            UsageStatus.RateLimited => "WarningBrush",
            _ => "DangerBrush"
        }) as System.Windows.Media.Brush;
        StatusDot.Fill = statusBrush;
        CompactStatusDot.Fill = statusBrush;
        CompactMessageDot.Fill = statusBrush;

        var (showClaude, showCodex) = _settings.ResolveServices(state);
        ApplyProviderLayout(showClaude, showCodex);

        if (showClaude || showCodex)
        {
            MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
            CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
            MessagePanel.Visibility = Visibility.Collapsed;
            CompactPanel.Visibility = _settings.WidgetLayout == WidgetLayout.SingleRow ? Visibility.Visible : Visibility.Collapsed;
            ComfortablePanel.Visibility = _settings.WidgetLayout == WidgetLayout.TwoRows ? Visibility.Visible : Visibility.Collapsed;
            CompactMessagePanel.Visibility = Visibility.Collapsed;
            SetMetric(FiveHourValue, FiveHourBar, state.Snapshot?.FiveHour);
            SetMetric(WeeklyValue, WeeklyBar, state.Snapshot?.Weekly);
            SetMetric(FableValue, FableBar, state.Snapshot?.Fable);
            SetMetric(CompactFiveHourValue, CompactFiveHourBar, state.Snapshot?.FiveHour);
            SetMetric(CompactWeeklyValue, CompactWeeklyBar, state.Snapshot?.Weekly);
            SetMetric(CompactFableValue, CompactFableBar, state.Snapshot?.Fable);
            var codexLimit = state.CodexSnapshot?.Weekly ?? state.CodexSnapshot?.FiveHour;
            SetMetric(CodexValue, CodexBar, codexLimit);
            SetMetric(CompactCodexValue, CompactCodexBar, codexLimit);
            CodexCredits.Text = FormatCredits(state.CodexSnapshot?.ResetCredits);
            CompactCodexCredits.Text = state.CodexSnapshot?.ResetCredits is int credits ? $"초기화권 {credits}" : "";
        }
        else
        {
            MetricsPanel.Visibility = Visibility.Collapsed;
            ComfortablePanel.Visibility = Visibility.Collapsed;
            MessagePanel.Visibility = Visibility.Visible;
            MessageText.Text = state.Message;
            CompactPanel.Visibility = Visibility.Collapsed;
            CompactMessagePanel.Visibility = Visibility.Visible;
            CompactMessageText.Text = state.Message;
        }
    }

    private void ApplyProviderLayout(bool showClaude, bool showCodex)
    {
        CompactClaudeFivePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeWeeklyPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeFablePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactCodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeFiveColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeWeeklyColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeFableColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeGapOne.Width = new GridLength(showClaude ? 10 : 0);
        CompactClaudeGapTwo.Width = new GridLength(showClaude ? 10 : 0);
        CompactProviderGap.Width = new GridLength(showClaude && showCodex ? 10 : 0);
        CompactCodexColumn.Width = new GridLength(showCodex ? 1.35 : 0, GridUnitType.Star);
        CodexRow.Height = showCodex ? GridLength.Auto : new GridLength(0);
        ClaudeRow.Height = showClaude ? GridLength.Auto : new GridLength(0);
        CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CodexPanel.Margin = new Thickness(0, showCodex ? 7 : 0, 0, 0);
        MetricsPanel.Margin = new Thickness(0, showClaude && showCodex ? 10 : showClaude ? 7 : 0, 0, 0);

        var compact = _settings.WidgetDensity == WidgetDensity.Compact;
        var singleRow = _settings.WidgetLayout == WidgetLayout.SingleRow;
        var providerCount = (showClaude ? 1 : 0) + (showCodex ? 1 : 0);
        if (providerCount == 0)
        {
            Width = compact ? 300 : 360;
            Height = compact ? 40 : 48;
            return;
        }

        Width = compact
            ? singleRow ? showClaude && showCodex ? 476 : showClaude ? 360 : 220
                        : showClaude && showCodex ? 452 : showClaude ? 400 : 340
            : singleRow ? showClaude && showCodex ? 520 : showClaude ? 420 : 280
                        : showClaude && showCodex ? 520 : 420;
        Height = singleRow
            ? (_settings.ShowProgressBars ? 46 : 36)
            : providerCount == 2
                ? compact
                    ? (_settings.ShowWidgetHeader ? 104 : 84)
                    : (_settings.ShowWidgetHeader ? 116 : 96)
                : compact
                    ? (_settings.ShowWidgetHeader ? 74 : 56)
                    : (_settings.ShowWidgetHeader ? 84 : 66);
    }

    internal void PositionFromSettings(bool forceDefault = false)
    {
        var screens = Forms.Screen.AllScreens;
        var primary = Forms.Screen.PrimaryScreen ?? screens[0];
        if (!forceDefault && _settings.WidgetPlacement == WidgetPlacement.Custom &&
            _settings.WidgetLeft is int savedLeft && _settings.WidgetTop is int savedTop)
        {
            var target = screens.FirstOrDefault(screen => screen.WorkingArea.Contains(savedLeft, savedTop)) ?? primary;
            var area = target.WorkingArea;
            Left = Math.Clamp(savedLeft, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(savedTop, area.Top, Math.Max(area.Top, area.Bottom - Height));
            return;
        }

        var work = primary.WorkingArea;
        Left = work.Right - Width - 12;
        Top = _settings.WidgetPlacement == WidgetPlacement.TopRight
            ? work.Top + 12
            : work.Bottom - Height - 8;
    }

    internal void KeepCurrentPositionVisible()
    {
        if (!IsLoaded || double.IsNaN(Left) || double.IsNaN(Top)) return;
        var screens = Forms.Screen.AllScreens;
        var primary = Forms.Screen.PrimaryScreen ?? screens[0];
        var center = new System.Drawing.Point((int)Math.Round(Left + Width / 2), (int)Math.Round(Top + Height / 2));
        var target = screens.FirstOrDefault(screen => screen.Bounds.Contains(center)) ?? primary;
        var area = target.WorkingArea;
        Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
        Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        if (_settings.WidgetPlacement != WidgetPlacement.Custom) return;
        _settings.WidgetLeft = (int)Math.Round(Left);
        _settings.WidgetTop = (int)Math.Round(Top);
    }

    private void OnWidgetMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        var before = PointToScreen(e.GetPosition(this));
        var origin = new System.Windows.Point(Left, Top);
        try { DragMove(); } catch (InvalidOperationException) { }
        var moved = Math.Abs(Left - origin.X) + Math.Abs(Top - origin.Y) > 3;
        if (moved)
        {
            _settings.WidgetPlacement = WidgetPlacement.Custom;
            _settings.WidgetLeft = (int)Math.Round(Left);
            _settings.WidgetTop = (int)Math.Round(Top);
            PositionChangedByUser?.Invoke(this, EventArgs.Empty);
        }
        else if (PointToScreen(Mouse.GetPosition(this)).Subtract(before).Length < 4)
        {
            WidgetClicked?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnWidgetRightClick(object sender, MouseButtonEventArgs e) =>
        SettingsRequested?.Invoke(this, EventArgs.Empty);

    private void SetMetric(System.Windows.Controls.TextBlock label, System.Windows.Controls.ProgressBar bar, UsageLimit? limit)
    {
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        label.Text = value is null ? "--%" : $"{value:0}%";
        bar.Value = value ?? 0;
        var brushKey = _settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "WarningBrush" : "AccentBrush";
        label.Foreground = FindResource(brushKey) as System.Windows.Media.Brush;
        bar.Foreground = FindResource(brushKey) as System.Windows.Media.Brush;
    }

    private static string FormatCredits(int? credits) => credits is null ? "초기화권 --" : $"초기화권 {credits}개";
}

internal static class PointExtensions
{
    public static Vector Subtract(this System.Windows.Point point, System.Windows.Point other) => point - other;
}
