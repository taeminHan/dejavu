using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace ClaudeUsageTray;

public partial class UsageWidgetWindow : Window
{
    private ApplicationState _state = ApplicationState.Loading();
    private TraySettings _settings;
    private bool _leftPointerDown;
    private bool _isDragging;
    private System.Windows.Point _pointerDownScreen;
    private System.Windows.Point _windowOrigin;

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
        var small = settings.WidgetDensity == WidgetDensity.Small;
        var compact = settings.WidgetDensity != WidgetDensity.Comfortable;
        var singleRow = settings.WidgetLayout == WidgetLayout.SingleRow;
        SmallPanel.Visibility = small ? Visibility.Visible : Visibility.Collapsed;
        CompactPanel.Visibility = !small && singleRow ? Visibility.Visible : Visibility.Collapsed;
        ComfortablePanel.Visibility = !small && !singleRow ? Visibility.Visible : Visibility.Collapsed;
        SmallProviderPanel.Orientation = singleRow ? System.Windows.Controls.Orientation.Horizontal : System.Windows.Controls.Orientation.Vertical;
        SmallCodexPanel.Margin = singleRow ? new Thickness(8, 0, 0, 0) : new Thickness(0, 8, 0, 0);
        SmallStatusDot.Visibility = settings.ShowWidgetHeader ? Visibility.Visible : Visibility.Collapsed;
        SmallStatusColumn.Width = new GridLength(settings.ShowWidgetHeader ? 10 : 0);
        CompactStatusDot.Visibility = settings.ShowWidgetHeader ? Visibility.Visible : Visibility.Collapsed;
        CompactStatusColumn.Width = new GridLength(settings.ShowWidgetHeader ? small ? 10 : 14 : 0);
        HeaderPanel.Visibility = settings.ShowWidgetHeader ? Visibility.Visible : Visibility.Collapsed;
        HeaderRow.Height = new GridLength(settings.ShowWidgetHeader ? 18 : 0);
        WidgetCard.Padding = small ? new Thickness(7, 6, 7, 6)
            : compact ? new Thickness(11, 9, 11, 9) : new Thickness(15, 12, 15, 12);
        WidgetCard.CornerRadius = new CornerRadius(small ? 9 : compact ? 11 : 14);
        var metricLabelSize = compact ? 10d : 11d;
        var metricValueSize = compact ? 12d : 13d;
        var linearBarMargin = compact ? 5d : 7d;
        foreach (var label in new[] { CompactFiveHourLabel, CompactWeeklyLabel, CompactFableLabel, CompactCodexLabel })
            label.FontSize = metricLabelSize;
        foreach (var value in new[] { CompactFiveHourValue, CompactWeeklyValue, CompactFableValue, CompactCodexValue })
            value.FontSize = metricValueSize;
        CompactFiveHourLabel.Text = compact ? "5H" : "5시간";
        CompactWeeklyLabel.Text = compact ? "주간" : "주간 전체";
        CompactFableLabel.Text = compact ? "Fable" : "주간 Fable";
        CompactCodexLabel.Text = "Codex";
        foreach (var bar in new[] { CompactFiveHourBar, CompactWeeklyBar, CompactFableBar, CompactCodexBar })
            bar.Margin = new Thickness(0, linearBarMargin, 0, 0);
        foreach (var label in new[] { FiveHourLabel, WeeklyLabel, FableLabel, CodexLabel })
            label.FontSize = metricLabelSize;
        foreach (var value in new[] { FiveHourValue, WeeklyValue, FableValue, CodexValue })
            value.FontSize = metricValueSize;
        FiveHourLabel.Text = compact ? "5H" : "5시간";
        WeeklyLabel.Text = compact ? "주간" : "주간 전체";
        FableLabel.Text = compact ? "Fable" : "주간 Fable";
        CodexLabel.Text = compact ? "Codex" : "Codex 주간";
        CodexCredits.FontSize = compact ? 8.5 : 9;
        foreach (var bar in new[] { FiveHourBar, WeeklyBar, FableBar, CodexBar })
            bar.Margin = new Thickness(0, linearBarMargin, 0, 0);
        foreach (var bar in new[] { FiveHourBar, WeeklyBar, FableBar, CodexBar, CompactFiveHourBar, CompactWeeklyBar, CompactFableBar, CompactCodexBar })
            bar.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
        foreach (var ring in new FrameworkElement[] { SmallFiveHourTrack, SmallFiveHourArc, SmallWeeklyTrack, SmallWeeklyArc, SmallFableTrack, SmallFableArc, SmallCodexTrack, SmallCodexArc })
            ring.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
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
        SmallStatusDot.Fill = statusBrush;
        CompactStatusDot.Fill = statusBrush;
        CompactMessageDot.Fill = statusBrush;

        var (showClaude, showCodex) = _settings.ResolveServices(state);
        ApplyProviderLayout(showClaude, showCodex);

        if (showClaude || showCodex)
        {
            MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
            CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
            MessagePanel.Visibility = Visibility.Collapsed;
            var small = _settings.WidgetDensity == WidgetDensity.Small;
            SmallPanel.Visibility = small ? Visibility.Visible : Visibility.Collapsed;
            CompactPanel.Visibility = !small && _settings.WidgetLayout == WidgetLayout.SingleRow ? Visibility.Visible : Visibility.Collapsed;
            ComfortablePanel.Visibility = !small && _settings.WidgetLayout == WidgetLayout.TwoRows ? Visibility.Visible : Visibility.Collapsed;
            CompactMessagePanel.Visibility = Visibility.Collapsed;
            SetMetric(FiveHourValue, FiveHourBar, state.Snapshot?.FiveHour);
            SetMetric(WeeklyValue, WeeklyBar, state.Snapshot?.Weekly);
            SetMetric(FableValue, FableBar, state.Snapshot?.Fable);
            SetMetric(CompactFiveHourValue, CompactFiveHourBar, state.Snapshot?.FiveHour);
            SetMetric(CompactWeeklyValue, CompactWeeklyBar, state.Snapshot?.Weekly);
            SetMetric(CompactFableValue, CompactFableBar, state.Snapshot?.Fable);
            SetCircularMetric(SmallFiveHourValue, SmallFiveHourArc, state.Snapshot?.FiveHour);
            SetCircularMetric(SmallWeeklyValue, SmallWeeklyArc, state.Snapshot?.Weekly);
            SetCircularMetric(SmallFableValue, SmallFableArc, state.Snapshot?.Fable);
            var codexLimit = state.CodexSnapshot?.Weekly ?? state.CodexSnapshot?.FiveHour;
            SetMetric(CodexValue, CodexBar, codexLimit);
            SetMetric(CompactCodexValue, CompactCodexBar, codexLimit);
            SetCircularMetric(SmallCodexValue, SmallCodexArc, codexLimit);
            CodexCredits.Text = _settings.WidgetDensity == WidgetDensity.Compact
                ? FormatCompactCredits(state.CodexSnapshot?.ResetCredits)
                : FormatCredits(state.CodexSnapshot?.ResetCredits);
            CompactCodexCredits.Text = FormatCompactCredits(state.CodexSnapshot?.ResetCredits);
            SmallCodexCredits.Text = FormatCompactCredits(state.CodexSnapshot?.ResetCredits);
        }
        else
        {
            MetricsPanel.Visibility = Visibility.Collapsed;
            SmallPanel.Visibility = Visibility.Collapsed;
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
        SmallClaudePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        SmallCodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeFiveColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeWeeklyColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeFableColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        var compactGap = _settings.WidgetDensity == WidgetDensity.Small ? 6 : 10;
        CompactClaudeGapOne.Width = new GridLength(showClaude ? compactGap : 0);
        CompactClaudeGapTwo.Width = new GridLength(showClaude ? compactGap : 0);
        CompactProviderGap.Width = new GridLength(showClaude && showCodex ? compactGap : 0);
        CompactCodexColumn.Width = new GridLength(showCodex ? 1 : 0, GridUnitType.Star);
        CodexRow.Height = showCodex ? GridLength.Auto : new GridLength(0);
        ClaudeRow.Height = showClaude ? GridLength.Auto : new GridLength(0);
        CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        var compact = _settings.WidgetDensity == WidgetDensity.Compact;
        var providerTop = _settings.ShowWidgetHeader ? (compact ? 7 : 9) : 0;
        var providerGap = compact ? 10 : 12;
        CodexPanel.Margin = new Thickness(0, showCodex ? providerTop : 0, 0, 0);
        MetricsPanel.Margin = new Thickness(0, showClaude && showCodex ? providerGap : showClaude ? providerTop : 0, 0, 0);

        var small = _settings.WidgetDensity == WidgetDensity.Small;
        var comfortable = _settings.WidgetDensity == WidgetDensity.Comfortable;
        var singleRow = _settings.WidgetLayout == WidgetLayout.SingleRow;
        var providerCount = (showClaude ? 1 : 0) + (showCodex ? 1 : 0);
        if (providerCount == 0)
        {
            Width = small ? 250 : comfortable ? 360 : 300;
            Height = small ? 34 : comfortable ? 48 : 40;
            return;
        }

        if (small)
        {
            // Include the status column and card padding in the window size. Without
            // these pixels the right-most reset-credit badge is clipped by the card.
            Width = showClaude ? 168 : 72;
            if (singleRow && showClaude && showCodex) Width = 224;
            Height = singleRow
                ? showCodex ? 82 : 60
                : providerCount == 2 ? 132 : showCodex ? 82 : 60;
            return;
        }

        if (singleRow)
        {
            Width = comfortable
                ? showClaude && showCodex ? 600 : showClaude ? 456 : 240
                : showClaude && showCodex ? 520 : showClaude ? 378 : 190;
            Height = _settings.ShowProgressBars
                ? comfortable ? 56 : 48
                : comfortable ? 44 : 38;
            return;
        }

        Width = comfortable
            ? showClaude ? 480 : 340
            : showClaude ? 400 : 260;
        var hiddenBarReduction = _settings.ShowProgressBars
            ? 0
            : providerCount * (comfortable ? 11 : 9);
        Height = (providerCount == 2
            ? comfortable
                ? (_settings.ShowWidgetHeader ? 124 : 104)
                : (_settings.ShowWidgetHeader ? 108 : 88)
            : comfortable
                ? (_settings.ShowWidgetHeader ? 88 : 68)
                : (_settings.ShowWidgetHeader ? 76 : 58)) - hiddenBarReduction;
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
        _leftPointerDown = true;
        _isDragging = false;
        _pointerDownScreen = PointToScreen(e.GetPosition(this));
        _windowOrigin = new System.Windows.Point(Left, Top);
        Mouse.Capture(WidgetCard);
        e.Handled = true;
    }

    private void OnWidgetMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_leftPointerDown || e.LeftButton != MouseButtonState.Pressed) return;
        var current = PointToScreen(e.GetPosition(this));
        var delta = current - _pointerDownScreen;
        if (!_isDragging &&
            Math.Abs(delta.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(delta.Y) < SystemParameters.MinimumVerticalDragDistance)
        {
            return;
        }

        _isDragging = true;
        Left = _windowOrigin.X + delta.X;
        Top = _windowOrigin.Y + delta.Y;
        e.Handled = true;
    }

    private void OnWidgetMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left || !_leftPointerDown) return;
        Mouse.Capture(null);
        var wasDragging = _isDragging;
        _leftPointerDown = false;
        _isDragging = false;
        if (wasDragging)
        {
            KeepCurrentPositionVisible();
            _settings.WidgetPlacement = WidgetPlacement.Custom;
            _settings.WidgetLeft = (int)Math.Round(Left);
            _settings.WidgetTop = (int)Math.Round(Top);
            PositionChangedByUser?.Invoke(this, EventArgs.Empty);
        }
        else WidgetClicked?.Invoke(this, EventArgs.Empty);
        e.Handled = true;
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

    private void SetCircularMetric(System.Windows.Controls.TextBlock label, System.Windows.Shapes.Path arc, UsageLimit? limit)
    {
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        label.Text = value is null ? "--%" : $"{value:0}%";
        arc.Data = CreateArcGeometry(value ?? 0);
        var brushKey = _settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "WarningBrush" : "AccentBrush";
        var brush = FindResource(brushKey) as System.Windows.Media.Brush;
        label.Foreground = brush;
        arc.Stroke = brush;
    }

    private static Geometry CreateArcGeometry(double percent)
    {
        const double size = 30;
        const double radius = 13.5;
        var center = new System.Windows.Point(size / 2, size / 2);
        var clamped = Math.Clamp(percent, 0, 100);
        if (clamped <= 0) return Geometry.Empty;

        var angle = clamped / 100d * 359.999;
        var start = new System.Windows.Point(center.X, center.Y - radius);
        var radians = (angle - 90) * Math.PI / 180d;
        var end = new System.Windows.Point(center.X + radius * Math.Cos(radians), center.Y + radius * Math.Sin(radians));
        var figure = new PathFigure { StartPoint = start, IsClosed = false };
        figure.Segments.Add(new ArcSegment(end, new System.Windows.Size(radius, radius), 0, angle > 180,
            SweepDirection.Clockwise, true));
        return new PathGeometry([figure]);
    }

    private static string FormatCredits(int? credits) => credits is null ? "초기화권 --" : $"초기화권 {credits}개";
    private static string FormatCompactCredits(int? credits) => credits is null ? "초기화권 --" : $"초기화권 {credits}";
}
