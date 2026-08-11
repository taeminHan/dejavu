using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace ClaudeUsageTray;

public partial class UsageWidgetWindow : Window
{
    private const int GwlExStyle = -20;
    private const long WsExTopmost = 0x00000008L;
    private const int WmShowWindow = 0x0018;
    private const int WmWindowPosChanged = 0x0047;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoOwnerZOrder = 0x0200;
    private static readonly nint HwndTopmost = new(-1);
    private static readonly uint TaskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
    private ApplicationState _state = ApplicationState.Loading();
    private TraySettings _settings;
    private bool _leftPointerDown;
    private bool _isDragging;
    private bool _topmostRepairPending;
    private System.Windows.Point _pointerDownScreen;
    private System.Windows.Point _windowOrigin;
    private nint _windowHandle;
    private HwndSource? _windowSource;
    private string _pendingTopmostRepairReason = "initial_show";

    internal UsageWidgetWindow(TraySettings settings)
    {
        InitializeComponent();
        _settings = settings;
        IsVisibleChanged += OnWidgetIsVisibleChanged;
        ApplySettings(settings);
    }

    internal event EventHandler? WidgetClicked;
    internal event EventHandler? SettingsRequested;
    internal event EventHandler? PositionChangedByUser;

    internal bool NativeTopmost => _windowHandle != nint.Zero && HasNativeTopmostStyle(_windowHandle);
    internal int TopmostRepairCount { get; private set; }
    internal DateTimeOffset? LastTopmostRepairAt { get; private set; }
    internal string? LastTopmostRepairReason { get; private set; }
    internal int? LastTopmostRepairError { get; private set; }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        _windowHandle = new WindowInteropHelper(this).Handle;
        _windowSource = HwndSource.FromHwnd(_windowHandle);
        _windowSource?.AddHook(WidgetWindowProc);
        RequestTopmostRepair("source_initialized");
    }

    protected override void OnClosed(EventArgs e)
    {
        IsVisibleChanged -= OnWidgetIsVisibleChanged;
        _windowSource?.RemoveHook(WidgetWindowProc);
        _windowSource = null;
        _windowHandle = nint.Zero;
        base.OnClosed(e);
    }

    internal void RequestTopmostRepair(string reason)
    {
        if (Dispatcher.HasShutdownStarted || Dispatcher.HasShutdownFinished) return;
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.BeginInvoke(DispatcherPriority.Background,
                new Action(() => RequestTopmostRepair(reason)));
            return;
        }

        _pendingTopmostRepairReason = reason;
        if (_topmostRepairPending) return;
        _topmostRepairPending = true;
        _ = Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
        {
            _topmostRepairPending = false;
            RepairTopmostIfNeeded(_pendingTopmostRepairReason);
        }));
    }

    private void OnWidgetIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (IsVisible) RequestTopmostRepair("visibility_restored");
    }

    private nint WidgetWindowProc(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if ((message == WmWindowPosChanged &&
             (!Topmost || !HasNativeTopmostStyle(hwnd))) ||
            (message == WmShowWindow && wParam != nint.Zero) ||
            (TaskbarCreatedMessage != 0 && unchecked((uint)message) == TaskbarCreatedMessage))
        {
            RequestTopmostRepair(message == WmWindowPosChanged
                ? "window_position_changed"
                : message == WmShowWindow ? "window_shown" : "explorer_restarted");
        }

        return nint.Zero;
    }

    private void RepairTopmostIfNeeded(string reason)
    {
        if (!IsVisible || _windowHandle == nint.Zero) return;
        var managedTopmost = Topmost;
        var nativeTopmost = HasNativeTopmostStyle(_windowHandle);
        if (managedTopmost && nativeTopmost) return;

        Topmost = true;
        var repaired = HasNativeTopmostStyle(_windowHandle) || SetWindowPos(
            _windowHandle, HwndTopmost, 0, 0, 0, 0,
            SwpNoMove | SwpNoSize | SwpNoActivate | SwpNoOwnerZOrder);
        LastTopmostRepairAt = DateTimeOffset.Now;
        LastTopmostRepairReason = reason;
        if (repaired)
        {
            TopmostRepairCount++;
            LastTopmostRepairError = null;
        }
        else
        {
            LastTopmostRepairError = Marshal.GetLastWin32Error();
        }
    }

    private static bool HasNativeTopmostStyle(nint handle) =>
        (GetWindowLongPtr(handle, GwlExStyle).ToInt64() & WsExTopmost) != 0;

    internal void ApplySettings(TraySettings settings)
    {
        _settings = settings;
        // Window opacity also fades text and progress graphics. Widget transparency
        // is applied only to the chrome brushes by ThemeManager.
        Opacity = 1.0;
        var theme = settings.WidgetTheme;
        var themed = ThemeManager.UsesThemedChrome(theme);
        var angular = ThemeManager.UsesAngularChrome(theme);
        var small = settings.WidgetDensity == WidgetDensity.Small;
        var compact = settings.WidgetDensity != WidgetDensity.Comfortable;
        var singleRow = settings.WidgetLayout == WidgetLayout.SingleRow;
        SmallPanel.Visibility = small ? Visibility.Visible : Visibility.Collapsed;
        CompactPanel.Visibility = !small && singleRow ? Visibility.Visible : Visibility.Collapsed;
        ComfortablePanel.Visibility = !small && !singleRow ? Visibility.Visible : Visibility.Collapsed;
        SmallProviderPanel.Orientation = singleRow ? System.Windows.Controls.Orientation.Horizontal : System.Windows.Controls.Orientation.Vertical;
        WidgetCard.Style = FindResource(ThemeManager.WidgetCardStyleKey(theme)) as Style;
        WidgetCard.Padding = themed ? new Thickness(0) : small ? new Thickness(7, 6, 7, 6)
            : compact ? new Thickness(11, 9, 11, 9) : new Thickness(15, 12, 15, 12);
        WidgetBody.Margin = themed
            ? small ? new Thickness(7, 6, 7, 6)
                : compact ? new Thickness(10, 8, 10, 8) : new Thickness(14, 10, 14, 11)
            : new Thickness(0);
        WidgetCard.CornerRadius = theme switch
        {
            WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono => new CornerRadius(0),
            WidgetVisualTheme.FluentGlass => new CornerRadius(small ? 12 : 18),
            WidgetVisualTheme.Orbit => new CornerRadius(small ? 12 : 16),
            WidgetVisualTheme.PaperInk => new CornerRadius(4),
            _ => new CornerRadius(small ? 9 : compact ? 11 : 14)
        };
        var widgetFont = FindResource("WidgetFontFamily") as System.Windows.Media.FontFamily
            ?? new System.Windows.Media.FontFamily("Segoe UI Variable Text");
        ThemeTextureOverlay.Visibility = theme is WidgetVisualTheme.RetroNight
            or WidgetVisualTheme.TerminalMono or WidgetVisualTheme.PaperInk
            ? Visibility.Visible : Visibility.Collapsed;
        var textureOpacity = theme == WidgetVisualTheme.TerminalMono ? 0.2
            : theme == WidgetVisualTheme.PaperInk ? 0.1 : 0.14;
        ThemeTextureOverlay.Opacity = textureOpacity * settings.WidgetOpacity;
        var metricLabelSize = compact ? 10d : 11d;
        var metricValueSize = compact ? 12d : 13d;
        var linearBarMargin = compact ? 5d : 7d;
        foreach (var label in new[] { CompactFiveHourLabel, CompactWeeklyLabel, CompactFableLabel, CompactCodexLabel })
            label.FontSize = metricLabelSize;
        foreach (var value in new[] { CompactFiveHourValue, CompactWeeklyValue, CompactFableValue, CompactCodexValue })
        {
            value.FontSize = metricValueSize;
            value.FontFamily = widgetFont;
        }
        CompactFiveHourLabel.Text = compact ? "5H" : "5시간";
        CompactWeeklyLabel.Text = compact ? "주간" : "주간 전체";
        CompactFableLabel.Text = compact ? "Fable" : "주간 Fable";
        CompactCodexLabel.Text = "Codex";
        foreach (var bar in new[] { CompactFiveHourBar, CompactWeeklyBar, CompactFableBar, CompactCodexBar })
            bar.Margin = new Thickness(0, linearBarMargin, 0, 0);
        foreach (var label in new[] { FiveHourLabel, WeeklyLabel, FableLabel, CodexLabel })
            label.FontSize = metricLabelSize;
        foreach (var value in new[] { FiveHourValue, WeeklyValue, FableValue, CodexValue })
        {
            value.FontSize = metricValueSize;
            value.FontFamily = widgetFont;
        }
        FiveHourLabel.Text = compact ? "5H" : "5시간";
        WeeklyLabel.Text = compact ? "주간" : "주간 전체";
        FableLabel.Text = compact ? "Fable" : "주간 Fable";
        CodexLabel.Text = compact ? "Codex" : "Codex 주간";
        foreach (var bar in new[] { FiveHourBar, WeeklyBar, FableBar, CodexBar })
            bar.Margin = new Thickness(0, linearBarMargin, 0, 0);
        foreach (var bar in new[] { FiveHourBar, WeeklyBar, FableBar, CodexBar, CompactFiveHourBar, CompactWeeklyBar, CompactFableBar, CompactCodexBar })
        {
            bar.Style = FindResource(ThemeManager.WidgetProgressStyleKey(theme)) as Style;
            bar.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
        }
        foreach (var value in new[] { SmallFiveHourValue, SmallWeeklyValue, SmallFableValue, SmallCodexValue })
            value.FontFamily = widgetFont;
        foreach (var track in new[] { SmallFiveHourTrack, SmallWeeklyTrack, SmallFableTrack, SmallCodexTrack })
        {
            track.StrokeThickness = theme is WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono or WidgetVisualTheme.Orbit ? 4 : 3;
            track.StrokeDashArray = theme == WidgetVisualTheme.PaperInk
                ? new DoubleCollection([1.1, 0.65]) : null;
        }
        foreach (var arc in new[] { SmallFiveHourArc, SmallWeeklyArc, SmallFableArc, SmallCodexArc })
        {
            arc.StrokeThickness = theme is WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono or WidgetVisualTheme.Orbit ? 4 : 3;
            arc.StrokeStartLineCap = angular ? PenLineCap.Flat : PenLineCap.Round;
            arc.StrokeEndLineCap = angular ? PenLineCap.Flat : PenLineCap.Round;
            arc.StrokeDashCap = PenLineCap.Round;
            arc.StrokeDashArray = theme == WidgetVisualTheme.PaperInk
                ? new DoubleCollection([1.15, 0.5]) : null;
        }
        ApplyThemeStructure(theme, compact);
        foreach (var ring in new FrameworkElement[] { SmallFiveHourTrack, SmallFiveHourArc, SmallWeeklyTrack, SmallWeeklyArc, SmallFableTrack, SmallFableArc, SmallCodexTrack, SmallCodexArc })
            ring.Visibility = settings.ShowProgressBars ? Visibility.Visible : Visibility.Collapsed;
        UpdateState(_state);
    }

    private void ApplyThemeStructure(WidgetVisualTheme theme, bool compact)
    {
        var compactCards = new[] { CompactFiveCard, CompactWeeklyCard, CompactFableCard, CompactCodexCard };
        var comfortableCards = new[] { ComfortableFiveCard, ComfortableWeeklyCard, ComfortableFableCard, ComfortableCodexCard };
        var allCards = compactCards.Concat(comfortableCards).ToArray();
        foreach (var card in allCards)
        {
            card.Background = System.Windows.Media.Brushes.Transparent;
            card.BorderBrush = System.Windows.Media.Brushes.Transparent;
            card.BorderThickness = new Thickness(0);
            card.CornerRadius = new CornerRadius(0);
            card.Padding = new Thickness(0);
        }

        var border = FindResource("WidgetBorderBrush") as System.Windows.Media.Brush;
        var raised = FindResource("WidgetChromeRaisedBrush") as System.Windows.Media.Brush;
        switch (theme)
        {
            case WidgetVisualTheme.RetroNight:
                foreach (var card in allCards)
                {
                    card.BorderBrush = border;
                    card.BorderThickness = new Thickness(1);
                    card.Padding = new Thickness(compact ? 5 : 7, compact ? 4 : 6, compact ? 5 : 7, compact ? 5 : 7);
                }
                break;
            case WidgetVisualTheme.FluentGlass:
                foreach (var card in allCards)
                {
                    card.Background = raised;
                    card.BorderBrush = border;
                    card.BorderThickness = new Thickness(1);
                    card.CornerRadius = new CornerRadius(compact ? 9 : 11);
                    card.Padding = new Thickness(compact ? 8 : 10, compact ? 6 : 8, compact ? 8 : 10, compact ? 7 : 9);
                }
                break;
            case WidgetVisualTheme.TerminalMono:
                foreach (var card in allCards)
                {
                    card.BorderBrush = border;
                    card.BorderThickness = new Thickness(1, 1, 1, 2);
                    card.Padding = new Thickness(compact ? 6 : 8, compact ? 5 : 7, compact ? 6 : 8, compact ? 6 : 8);
                }
                CompactFiveHourLabel.Text = "[5H]";
                CompactWeeklyLabel.Text = "[WEEK]";
                CompactFableLabel.Text = "[FABLE]";
                CompactCodexLabel.Text = "[CODEX]";
                break;
            case WidgetVisualTheme.Orbit:
                foreach (var card in allCards)
                {
                    card.BorderBrush = border;
                    card.BorderThickness = new Thickness(1);
                    card.CornerRadius = new CornerRadius(14);
                    card.Padding = new Thickness(compact ? 8 : 10, compact ? 7 : 9, compact ? 8 : 10, compact ? 8 : 10);
                }
                foreach (var value in new[] { CompactFiveHourValue, CompactWeeklyValue, CompactFableValue, CompactCodexValue,
                             FiveHourValue, WeeklyValue, FableValue, CodexValue })
                    value.FontSize = compact ? 13 : 14;
                break;
            case WidgetVisualTheme.PaperInk:
                foreach (var card in allCards)
                {
                    card.BorderBrush = border;
                    card.BorderThickness = new Thickness(0);
                    card.Padding = new Thickness(3, 3, 3, compact ? 7 : 9);
                }
                CompactFiveHourLabel.Text = "01 / 5H";
                CompactWeeklyLabel.Text = "02 / 주간";
                CompactFableLabel.Text = "03 / Fable";
                CompactCodexLabel.Text = "04 / Codex";
                break;
        }
    }

    internal void UpdateState(ApplicationState state)
    {
        var previousWidth = Width;
        var previousHeight = Height;
        _state = state;
        var statusBrush = FindResource(state.Status switch
        {
            UsageStatus.Ready or UsageStatus.Loading => ThemeManager.UsesThemedChrome(_settings.WidgetTheme)
                ? "WidgetAccentBrush" : "AccentBrush",
            UsageStatus.RateLimited => "WarningBrush",
            _ => "DangerBrush"
        }) as System.Windows.Media.Brush;
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
            SetCircularMetric(SmallFiveHourValue, SmallFiveHourArc, SmallFiveHourPlanet, state.Snapshot?.FiveHour);
            SetCircularMetric(SmallWeeklyValue, SmallWeeklyArc, SmallWeeklyPlanet, state.Snapshot?.Weekly);
            SetCircularMetric(SmallFableValue, SmallFableArc, SmallFablePlanet, state.Snapshot?.Fable);
            var codexLimit = state.CodexSnapshot?.Weekly ?? state.CodexSnapshot?.FiveHour;
            SetMetric(CodexValue, CodexBar, codexLimit);
            SetMetric(CompactCodexValue, CompactCodexBar, codexLimit);
            SetCircularMetric(SmallCodexValue, SmallCodexArc, SmallCodexPlanet, codexLimit);
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

        PreservePositionAfterResize(previousWidth, previousHeight);
    }

    private void ApplyProviderLayout(bool showClaude, bool showCodex)
    {
        var layout = WidgetLayoutCalculator.Calculate(new WidgetLayoutRequest(
            _settings.WidgetDensity,
            _settings.WidgetLayout,
            _settings.WidgetTheme,
            showClaude,
            showCodex,
            _settings.ShowProgressBars));
        CompactClaudeFivePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeWeeklyPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactClaudeFablePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactCodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        CompactFiveCard.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactWeeklyCard.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactFableCard.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        CompactCodexCard.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        SmallClaudePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        SmallCodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        SmallCodexPanel.Margin = new Thickness(layout.SmallCodexMarginLeft, layout.SmallCodexMarginTop, 0, 0);
        CompactClaudeFiveColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeWeeklyColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeFableColumn.Width = new GridLength(showClaude ? 1 : 0, GridUnitType.Star);
        CompactClaudeGapOne.Width = new GridLength(showClaude ? layout.CompactGap : 0);
        CompactClaudeGapTwo.Width = new GridLength(showClaude ? layout.CompactGap : 0);
        CompactProviderGap.Width = new GridLength(showClaude && showCodex ? layout.CompactGap : 0);
        CompactCodexColumn.Width = new GridLength(showCodex ? 1 : 0, GridUnitType.Star);
        CodexRow.Height = showCodex ? GridLength.Auto : new GridLength(0);
        ClaudeRow.Height = showClaude ? GridLength.Auto : new GridLength(0);
        CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        ComfortableCodexCard.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        ComfortableGapOne.Width = new GridLength(layout.ComfortableGap);
        ComfortableGapTwo.Width = new GridLength(layout.ComfortableGap);
        CodexPanel.Margin = new Thickness(0, showCodex ? layout.ProviderTop : 0, 0, 0);
        MetricsPanel.Margin = new Thickness(0,
            showClaude && showCodex ? layout.ProviderGap : showClaude ? layout.ProviderTop : 0, 0, 0);
        Width = layout.Width;
        Height = layout.Height;
    }

    private void PreservePositionAfterResize(double previousWidth, double previousHeight)
    {
        if (!IsLoaded || (Math.Abs(Width - previousWidth) < 0.5 && Math.Abs(Height - previousHeight) < 0.5))
            return;

        if (_settings.WidgetPlacement == WidgetPlacement.Custom) KeepCurrentPositionVisible();
        else PositionFromSettings(forceDefault: true);
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
        var thresholdBrushKey = _settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "WarningBrush" : null;
        label.Foreground = FindResource(thresholdBrushKey ?? "WidgetMetricTextBrush") as System.Windows.Media.Brush;
        bar.Foreground = FindResource(thresholdBrushKey ?? "WidgetAccentBrush") as System.Windows.Media.Brush;
    }

    private void SetCircularMetric(System.Windows.Controls.TextBlock label, System.Windows.Shapes.Path arc,
        System.Windows.Shapes.Ellipse planet, UsageLimit? limit)
    {
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        label.Text = value is null ? "--%" : $"{value:0}%";
        arc.Data = CreateArcGeometry(value ?? 0);
        var thresholdBrushKey = _settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "WarningBrush" : null;
        var metricBrush = FindResource(thresholdBrushKey ?? "WidgetMetricTextBrush") as System.Windows.Media.Brush;
        var progressBrush = FindResource(thresholdBrushKey ?? "WidgetAccentBrush") as System.Windows.Media.Brush;
        label.Foreground = metricBrush;
        arc.Stroke = progressBrush;
        var showPlanet = _settings.WidgetTheme == WidgetVisualTheme.Orbit &&
                         _settings.ShowProgressBars && value is > 0;
        planet.Visibility = showPlanet ? Visibility.Visible : Visibility.Collapsed;
        planet.Fill = progressBrush;
        if (showPlanet)
        {
            var angle = -90 + value!.Value / 100d * 359.999;
            var radians = angle * Math.PI / 180d;
            planet.RenderTransform = new TranslateTransform(13.5 * Math.Cos(radians), 13.5 * Math.Sin(radians));
        }
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

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint handle, int index);

    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern uint RegisterWindowMessage(string message);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint handle, nint insertAfter, int x, int y, int width, int height,
        uint flags);

}
