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
    private const int WmSysColorChange = 0x0015;
    private const int WmShowWindow = 0x0018;
    private const int WmWindowPosChanged = 0x0047;
    private const int WmThemeChanged = 0x031A;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoOwnerZOrder = 0x0200;
    private const uint GwHwndPrev = 3;
    // The walk ends by itself at the top of the z-order, where GetWindow returns 0. The bound only
    // guards against concurrent reordering; it is the per-session USER handle ceiling, so hidden
    // topmost windows (leaked tooltips, IME helpers) between the widget and the taskbar never exceed it.
    private const int TaskbarCoverWalkLimit = 65536;
    private const long TaskbarRaiseMinimumIntervalMilliseconds = 250;
    private const long TaskbarRaiseWindowMilliseconds = 60_000;
    private const int TaskbarRaiseMaximumPerWindow = 60;
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
    private readonly Queue<long> _taskbarRaiseTicks = new();
    private long? _lastTaskbarRaiseTick;
    private bool _taskbarRaiseBlocked;
    // The foreground window when the raise block was set; any other foreground window lifts it.
    private nint _taskbarRaiseBlockedForeground;
    private bool _taskbarPaletteRefreshPending;
    private TaskbarDock? _taskbarDock;
    private TaskbarLayoutMetrics? _taskbarLayout;
    // True while ApplySettings has applied the in-taskbar chrome. Layout and
    // positioning follow this instead of re-reading the shared settings object.
    private bool _taskbarLayoutActive;

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
    internal bool IsTaskbarDocked =>
        _settings.WidgetPlacement == WidgetPlacement.InTaskbar && _taskbarDock is not null;
    internal int TaskbarRaiseCount { get; private set; }
    internal DateTimeOffset? LastTaskbarRaiseAt { get; private set; }
    internal string? LastTaskbarRaiseReason { get; private set; }
    internal int? LastTaskbarRaiseError { get; private set; }
    // Set only for application shutdown; every other close request is cancelled.
    internal bool AllowClose { get; set; }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Alt+F4 or an external WM_CLOSE must not destroy the always-visible widget: the controller
        // shows this instance again after hides and settings changes, and Show() on a closed Window throws.
        if (!AllowClose) e.Cancel = true;
        base.OnClosing(e);
    }

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
        // A contrast-theme or system-color change leaves the tracker's dock unchanged.
        if (message is WmSysColorChange or WmThemeChanged) RequestTaskbarPaletteRefresh();
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

    /// <summary>
    /// Re-applies the docked palette after a system-color or theme broadcast. Background priority
    /// runs after WPF has processed the same broadcast; ApplyTaskbarPalette reads the current
    /// high-contrast colors itself, and resource references pick up the replaced brushes. The
    /// high-contrast flag is read live because the tracker may not have re-evaluated the dock yet.
    /// </summary>
    private void RequestTaskbarPaletteRefresh()
    {
        if (!_taskbarLayoutActive || _taskbarPaletteRefreshPending ||
            Dispatcher.HasShutdownStarted || Dispatcher.HasShutdownFinished)
            return;
        _taskbarPaletteRefreshPending = true;
        _ = Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
        {
            _taskbarPaletteRefreshPending = false;
            if (_taskbarLayoutActive && _taskbarDock is TaskbarDock dock)
                ThemeManager.ApplyTaskbarPalette(dock.LightTaskbar, ThemeManager.IsHighContrastOn());
        }));
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

    /// <summary>
    /// Receives the tracker's device-pixel taskbar band, or null when the overlay
    /// cannot dock (fallback or inactive). Safe before the HWND exists: layout is
    /// applied immediately, a size change re-anchors through UpdateState, and the
    /// explicit reposition below waits until the window has loaded.
    /// </summary>
    internal void SetTaskbarDock(TaskbarDock? dock)
    {
        if (_taskbarDock == dock && _taskbarLayoutActive == IsTaskbarDocked) return;
        _taskbarDock = dock;
        if (_taskbarLayoutActive != IsTaskbarDocked)
        {
            _taskbarRaiseBlocked = false;
            ApplySettings(_settings);
        }
        else
        {
            if (_taskbarLayoutActive && dock is TaskbarDock docked)
                ThemeManager.ApplyTaskbarPalette(docked.LightTaskbar, docked.HighContrast);
            UpdateState(_state);
        }

        // Only the in-taskbar placement reads the dock. Other placements keep
        // their position here so a custom top-left point never moves.
        if (IsLoaded && _settings.WidgetPlacement == WidgetPlacement.InTaskbar)
            PositionFromSettings(forceDefault: true);
    }

    /// <summary>
    /// Scoped exception to "never push to the front", active only while docked in
    /// the taskbar. Explorer's taskbar is itself topmost and moves to the front of
    /// the topmost band when clicked. When a local z-order walk finds it above the
    /// widget, insert the widget directly above the taskbar: no activation, no
    /// move or resize, and never above windows that were already above the taskbar.
    /// </summary>
    internal void RaiseAboveTaskbarIfCovered(nint taskbarHandle, string reason)
    {
        // A blocked raise waits for the shell to end the Start menu or flyout band that
        // holds the taskbar above the widget. Only the periodic backstop honors the block:
        // a foreground burst ("foreground" and its follow-ups) or the controller's "docked"
        // check can follow the end of that band. The backstop also lifts it once another
        // window is in the foreground, which covers changes that never arrive as a request:
        // Dejavu's own windows (skipped by the hook) and changes while the widget was hidden.
        if (_taskbarRaiseBlocked &&
            (reason != "backstop" || GetForegroundWindow() != _taskbarRaiseBlockedForeground))
            _taskbarRaiseBlocked = false;
        if (!IsVisible || !IsTaskbarDocked || _windowHandle == nint.Zero || taskbarHandle == nint.Zero ||
            _taskbarRaiseBlocked || !IsCoveredBy(taskbarHandle))
            return;

        var now = Environment.TickCount64;
        while (_taskbarRaiseTicks.Count > 0 && now - _taskbarRaiseTicks.Peek() >= TaskbarRaiseWindowMilliseconds)
            _taskbarRaiseTicks.Dequeue();
        if (_taskbarRaiseTicks.Count >= TaskbarRaiseMaximumPerWindow ||
            (_lastTaskbarRaiseTick is long last && now - last < TaskbarRaiseMinimumIntervalMilliseconds))
            return;

        var insertAfter = GetWindow(taskbarHandle, GwHwndPrev);
        if (insertAfter == _windowHandle) return;
        if (insertAfter == nint.Zero) insertAfter = HwndTopmost;
        _lastTaskbarRaiseTick = now;
        _taskbarRaiseTicks.Enqueue(now);
        var raised = SetWindowPos(_windowHandle, insertAfter, 0, 0, 0, 0,
            SwpNoMove | SwpNoSize | SwpNoActivate | SwpNoOwnerZOrder);
        LastTaskbarRaiseError = raised ? (int?)null : Marshal.GetLastWin32Error();
        LastTaskbarRaiseAt = DateTimeOffset.Now;
        LastTaskbarRaiseReason = reason;
        if (raised) TaskbarRaiseCount++;

        // Still covered means the shell holds the taskbar in a higher band
        // (Start, a system flyout). Do not compete; wait for a foreground change.
        if (IsCoveredBy(taskbarHandle))
        {
            _taskbarRaiseBlocked = true;
            _taskbarRaiseBlockedForeground = GetForegroundWindow();
        }
    }

    private bool IsCoveredBy(nint coveringHandle)
    {
        var current = _windowHandle;
        for (var step = 0; step < TaskbarCoverWalkLimit && current != nint.Zero; step++)
        {
            current = GetWindow(current, GwHwndPrev);
            if (current == coveringHandle) return true;
        }
        return false;
    }

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
        _taskbarLayoutActive = IsTaskbarDocked;
        if (_taskbarLayoutActive && _taskbarDock is TaskbarDock dock) ApplyTaskbarChrome(dock);
        else
        {
            WidgetCard.ClearValue(FrameworkElement.ToolTipProperty);
            WidgetCard.ClearValue(System.Windows.Automation.AutomationProperties.NameProperty);
        }
        UpdateState(_state);
    }

    /// <summary>
    /// The in-taskbar card blends into the taskbar, so the visual theme's card
    /// style, radius, texture and body inset are replaced. Card padding comes
    /// from TaskbarLayoutMetrics in ApplyProviderLayout.
    /// </summary>
    private void ApplyTaskbarChrome(TaskbarDock dock)
    {
        ThemeManager.ApplyTaskbarPalette(dock.LightTaskbar, dock.HighContrast);
        WidgetCard.Style = FindResource("WidgetCardTaskbar") as Style;
        WidgetCard.CornerRadius = new CornerRadius(4);
        WidgetBody.Margin = new Thickness(0);
        ThemeTextureOverlay.Visibility = Visibility.Collapsed;
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
        var layout = ApplyProviderLayout(showClaude, showCodex);

        TaskbarPanel.Visibility = _taskbarLayoutActive ? Visibility.Visible : Visibility.Collapsed;
        if (_taskbarLayoutActive)
        {
            UpdateTaskbarState(state, showClaude, showCodex);
        }
        else if (showClaude || showCodex)
        {
            MetricsPanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
            CodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
            MessagePanel.Visibility = Visibility.Collapsed;
            var small = _settings.WidgetDensity == WidgetDensity.Small;
            SmallPanel.Visibility = small ? Visibility.Visible : Visibility.Collapsed;
            CompactPanel.Visibility = !small && layout.EffectiveLayout == WidgetLayout.SingleRow ? Visibility.Visible : Visibility.Collapsed;
            ComfortablePanel.Visibility = !small && layout.EffectiveLayout == WidgetLayout.TwoRows ? Visibility.Visible : Visibility.Collapsed;
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

    /// <summary>
    /// In-taskbar values. Only TaskbarPanel is visible, hidden providers were
    /// collapsed by ApplyProviderLayout, and reset credits never appear here.
    /// </summary>
    private void UpdateTaskbarState(ApplicationState state, bool showClaude, bool showCodex)
    {
        SmallPanel.Visibility = Visibility.Collapsed;
        CompactPanel.Visibility = Visibility.Collapsed;
        ComfortablePanel.Visibility = Visibility.Collapsed;
        MessagePanel.Visibility = Visibility.Collapsed;
        CompactMessagePanel.Visibility = Visibility.Collapsed;

        var summary = new List<string>(4);
        if (showClaude)
        {
            summary.Add($"Claude 5시간 {SetTaskbarMetric(TaskbarFiveHourValue, TaskbarFiveHourBar, state.Snapshot?.FiveHour)}");
            summary.Add($"주간 {SetTaskbarMetric(TaskbarWeeklyValue, TaskbarWeeklyBar, state.Snapshot?.Weekly)}");
            summary.Add($"Fable {SetTaskbarMetric(TaskbarFableValue, TaskbarFableBar, state.Snapshot?.Fable)}");
        }
        if (showCodex)
        {
            var codexLimit = state.CodexSnapshot?.Weekly ?? state.CodexSnapshot?.FiveHour;
            summary.Add($"Codex {SetTaskbarMetric(TaskbarCodexValue, TaskbarCodexBar, codexLimit)}");
        }

        // The provider cells carry no status line and the no-provider cell shows only the
        // fixed "dejavu" placeholder, so the tooltip and the accessible name give the full
        // reading (or state.Message) in one short sentence.
        var description = summary.Count > 0 ? string.Join(" · ", summary) : state.Message;
        WidgetCard.ToolTip = description;
        System.Windows.Automation.AutomationProperties.SetName(WidgetCard, description);
    }

    private WidgetLayoutMetrics ApplyProviderLayout(bool showClaude, bool showCodex)
    {
        var layout = WidgetLayoutCalculator.Calculate(new WidgetLayoutRequest(
            _settings.WidgetDensity,
            _settings.WidgetLayout,
            _settings.WidgetTheme,
            showClaude,
            showCodex,
            _settings.ShowProgressBars,
            InTaskbar: _taskbarLayoutActive,
            TaskbarBandHeight: TaskbarBandHeightDip()));
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
        SmallProviderPanel.Orientation = layout.EffectiveLayout == WidgetLayout.SingleRow
            ? System.Windows.Controls.Orientation.Horizontal
            : System.Windows.Controls.Orientation.Vertical;
        SetSmallProviderOrder(layout.EffectiveLayout == WidgetLayout.TwoRows);
        SmallClaudePanel.Margin = new Thickness(0, layout.SmallClaudeMarginTop, 0, 0);
        SmallCodexPanel.Margin = new Thickness(layout.SmallCodexMarginLeft, 0, 0, 0);
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
        _taskbarLayout = layout.Taskbar;
        if (layout.Taskbar is TaskbarLayoutMetrics taskbar) ApplyTaskbarLayout(taskbar, showClaude, showCodex);
        Width = layout.Width;
        Height = layout.Height;
        return layout;
    }

    /// <summary>
    /// Applies TaskbarLayoutMetrics to the fixed taskbar cells. Only gaps between
    /// visible cells remain: the first Claude cell has no leading margin, and the
    /// provider gap precedes Codex only while Claude is visible.
    /// </summary>
    private void ApplyTaskbarLayout(TaskbarLayoutMetrics metrics, bool showClaude, bool showCodex)
    {
        WidgetCard.Padding = new Thickness(metrics.PaddingX, metrics.PaddingY, metrics.PaddingX, metrics.PaddingY);
        TaskbarClaudePanel.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        TaskbarCodexPanel.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        TaskbarMessageCell.Visibility = showClaude || showCodex ? Visibility.Collapsed : Visibility.Visible;
        TaskbarClaudePanel.Margin = new Thickness(0);
        TaskbarFiveCell.Margin = new Thickness(0);
        TaskbarWeeklyCell.Margin = new Thickness(metrics.CellGap, 0, 0, 0);
        TaskbarFableCell.Margin = new Thickness(metrics.CellGap, 0, 0, 0);
        TaskbarCodexPanel.Margin = new Thickness(showClaude && showCodex ? metrics.ProviderGap : 0, 0, 0, 0);
        TaskbarMessageCell.Margin = new Thickness(0);
        foreach (var cell in new[] { TaskbarFiveCell, TaskbarWeeklyCell, TaskbarFableCell, TaskbarCodexPanel, TaskbarMessageCell })
            cell.Width = metrics.CellWidth;
        foreach (var label in new[] { TaskbarFiveHourLabel, TaskbarWeeklyLabel, TaskbarFableLabel, TaskbarCodexLabel, TaskbarMessageLabel })
            label.LineHeight = metrics.LabelLineHeight;
        foreach (var value in new[] { TaskbarFiveHourValue, TaskbarWeeklyValue, TaskbarFableValue, TaskbarCodexValue, TaskbarMessageValue })
            value.LineHeight = metrics.ValueLineHeight;
        foreach (var (bar, providerVisible) in new[]
                 {
                     (TaskbarFiveHourBar, showClaude), (TaskbarWeeklyBar, showClaude),
                     (TaskbarFableBar, showClaude), (TaskbarCodexBar, showCodex)
                 })
        {
            bar.Height = metrics.ProgressHeight;
            bar.Margin = new Thickness(metrics.ProgressSideMargin, metrics.ProgressTopMargin,
                metrics.ProgressSideMargin, 0);
            bar.Visibility = metrics.ProgressVisible && providerVisible ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void SetSmallProviderOrder(bool codexFirst)
    {
        var first = codexFirst ? SmallCodexPanel : SmallClaudePanel;
        if (SmallProviderPanel.Children.IndexOf(first) == 0) return;
        SmallProviderPanel.Children.Remove(first);
        SmallProviderPanel.Children.Insert(0, first);
    }

    private void PreservePositionAfterResize(double previousWidth, double previousHeight)
    {
        if (Math.Abs(Width - previousWidth) < 0.5 && Math.Abs(Height - previousHeight) < 0.5)
            return;

        // Custom keeps its top-left point and only clamps once loaded (KeepCurrentPositionVisible checks
        // IsLoaded). Anchored placements re-anchor on every size change, including the gap between the
        // first Show() and Loaded, when the HWND already exists but IsLoaded is still false.
        if (_settings.WidgetPlacement == WidgetPlacement.Custom) KeepCurrentPositionVisible();
        else PositionFromSettings(forceDefault: true);
    }

    internal void PositionFromSettings(bool forceDefault = false)
    {
        if (_taskbarLayoutActive && _taskbarDock is TaskbarDock dock)
        {
            PositionInTaskbar(dock);
            return;
        }

        // Screen rectangles are device pixels; Left, Top and the saved custom
        // point are DIPs. The conversion is the identity at 100% scaling.
        var screens = Forms.Screen.AllScreens;
        var primary = Forms.Screen.PrimaryScreen ?? screens[0];
        if (!forceDefault && _settings.WidgetPlacement == WidgetPlacement.Custom &&
            _settings.WidgetLeft is int savedLeft && _settings.WidgetTop is int savedTop)
        {
            var savedPixels = DipToDevicePoint(savedLeft, savedTop);
            var target = screens.FirstOrDefault(screen => screen.WorkingArea.Contains(savedPixels)) ?? primary;
            var area = DeviceToDipRect(target.WorkingArea);
            Left = Math.Clamp(savedLeft, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(savedTop, area.Top, Math.Max(area.Top, area.Bottom - Height));
            return;
        }

        // InTaskbar without a dock (fallback) uses the taskbar-right formula.
        var work = DeviceToDipRect(primary.WorkingArea);
        Left = work.Right - Width - 12;
        Top = _settings.WidgetPlacement == WidgetPlacement.TopRight
            ? work.Top + 12
            : work.Bottom - Height - 8;
    }

    /// <summary>
    /// Pixel-snapped overlay placement: the right edge ends AnchorGap left of the
    /// notification area and the card is centred in the taskbar band. Working in
    /// whole device pixels keeps the edges crisp at fractional scaling.
    /// </summary>
    private void PositionInTaskbar(TaskbarDock dock)
    {
        var (scaleX, scaleY) = DevicePixelsPerDip();
        // WPF sizes the HWND rounding halves up, so predict the same pixel size here.
        var widthPixels = (int)Math.Round(Width * scaleX, MidpointRounding.AwayFromZero);
        var heightPixels = (int)Math.Round(Height * scaleY, MidpointRounding.AwayFromZero);
        var gapPixels = (int)Math.Round((_taskbarLayout?.AnchorGap ?? 0) * scaleX);
        var leftPixels = Math.Max(dock.BandLeftPixels, dock.AnchorRightPixels - gapPixels - widthPixels);
        var topPixels = dock.BandTopPixels + (int)Math.Round((dock.BandHeightPixels - heightPixels) / 2d);
        Left = leftPixels / scaleX;
        Top = topPixels / scaleY;
    }

    internal void KeepCurrentPositionVisible()
    {
        if (!IsLoaded || double.IsNaN(Left) || double.IsNaN(Top)) return;
        // The in-taskbar overlay intentionally sits outside the working area and
        // is positioned only by PositionFromSettings.
        if (_settings.WidgetPlacement == WidgetPlacement.InTaskbar) return;
        var screens = Forms.Screen.AllScreens;
        var primary = Forms.Screen.PrimaryScreen ?? screens[0];
        var center = DipToDevicePoint(Left + Width / 2, Top + Height / 2);
        var target = screens.FirstOrDefault(screen => screen.Bounds.Contains(center)) ?? primary;
        var area = DeviceToDipRect(target.WorkingArea);
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
        // The in-taskbar placement is anchored to the notification area, so a
        // press-move-release stays a click and never converts to Custom.
        if (_settings.WidgetPlacement == WidgetPlacement.InTaskbar) return;
        var current = PointToScreen(e.GetPosition(this));
        // PointToScreen reports device pixels; Left and Top are DIPs.
        var delta = DeviceToDip(this).Transform(current - _pointerDownScreen);
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

    private string SetTaskbarMetric(System.Windows.Controls.TextBlock label, System.Windows.Controls.ProgressBar bar,
        UsageLimit? limit)
    {
        // Clamp once: the text, the bar and the returned summary share one value.
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        var text = value is null ? "--%" : $"{value:0}%";
        label.Text = text;
        bar.Value = value ?? 0;
        var thresholdBrushKey = _settings.UseThresholdColors && value >= 90 ? "TaskbarDangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "TaskbarWarningBrush" : null;
        // Resource references follow ApplyTaskbarPalette when the taskbar theme changes.
        label.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty,
            thresholdBrushKey ?? "TaskbarTextBrush");
        bar.SetResourceReference(System.Windows.Controls.Control.ForegroundProperty,
            thresholdBrushKey ?? "TaskbarAccentBrush");
        return text;
    }

    private void SetCircularMetric(System.Windows.Controls.TextBlock label, System.Windows.Shapes.Path arc,
        OrbitBodyMarker planet, UsageLimit? limit)
    {
        var value = limit is null ? (double?)null : Math.Clamp(limit.Percent, 0, 100);
        label.Text = value is null ? "--%" : $"{value:0}%";
        arc.Data = CreateArcGeometry(value ?? 0);
        var thresholdBrushKey = _settings.UseThresholdColors && value >= 90 ? "DangerBrush"
            : _settings.UseThresholdColors && value >= 70 ? "WarningBrush" : null;
        var metricBrush = FindResource(thresholdBrushKey ?? "WidgetMetricTextBrush") as System.Windows.Media.Brush;
        var progressBrush = FindResource(thresholdBrushKey ?? "WidgetAccentBrush") as System.Windows.Media.Brush
                            ?? System.Windows.Media.Brushes.Transparent;
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

    private double TaskbarBandHeightDip() => _taskbarDock is TaskbarDock dock
        ? dock.BandHeightPixels * DeviceToDip(this).M22
        : WidgetLayoutCalculator.DefaultTaskbarBandHeight;

    /// <summary>
    /// Device-pixel to DIP transform for a visual. WPF makes the process
    /// system-DPI aware, so WinForms Screen rectangles, PointToScreen results and
    /// the taskbar tracker all report device pixels. Before an HWND exists the
    /// visual's reported DPI is used instead.
    /// </summary>
    internal static System.Windows.Media.Matrix DeviceToDip(System.Windows.Media.Visual visual)
    {
        if (PresentationSource.FromVisual(visual)?.CompositionTarget is CompositionTarget target)
            return target.TransformFromDevice;
        var dpi = VisualTreeHelper.GetDpi(visual);
        return new System.Windows.Media.Matrix(
            dpi.DpiScaleX > 0 ? 1 / dpi.DpiScaleX : 1, 0,
            0, dpi.DpiScaleY > 0 ? 1 / dpi.DpiScaleY : 1,
            0, 0);
    }

    private (double X, double Y) DevicePixelsPerDip()
    {
        var transform = DeviceToDip(this);
        return (transform.M11 > 0 ? 1 / transform.M11 : 1, transform.M22 > 0 ? 1 / transform.M22 : 1);
    }

    private System.Drawing.Point DipToDevicePoint(double x, double y)
    {
        var (scaleX, scaleY) = DevicePixelsPerDip();
        return new System.Drawing.Point((int)Math.Round(x * scaleX), (int)Math.Round(y * scaleY));
    }

    private System.Windows.Rect DeviceToDipRect(System.Drawing.Rectangle pixels)
    {
        var transform = DeviceToDip(this);
        return new System.Windows.Rect(
            transform.Transform(new System.Windows.Point(pixels.Left, pixels.Top)),
            transform.Transform(new System.Windows.Point(pixels.Right, pixels.Bottom)));
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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint GetWindow(nint handle, uint command);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

}
