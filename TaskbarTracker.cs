using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;

namespace ClaudeUsageTray;

internal enum TaskbarDockStatus { Inactive, Docked, Suppressed, Fallback }

/// <summary>
/// Device-pixel geometry (the process's system-DPI-aware coordinate space) of the primary taskbar band.
/// </summary>
internal readonly record struct TaskbarDock(
    int BandLeftPixels, int BandTopPixels, int BandRightPixels, int BandBottomPixels,
    int AnchorRightPixels,   // the widget's right edge must end at or left of this x (tray left, minus widgets allowance)
    bool LightTaskbar,       // HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize SystemUsesLightTheme == 1
    bool HighContrast)       // live SPI_GETHIGHCONTRAST HCF_HIGHCONTRASTON (ThemeManager.IsHighContrastOn)
{
    internal int BandHeightPixels => BandBottomPixels - BandTopPixels;
}

internal readonly record struct TaskbarTrackerState(
    TaskbarDockStatus Status,
    string Reason,           // "" when Docked/Inactive; otherwise a TaskbarTracker reason code
    TaskbarDock? Dock,       // non-null only when Docked
    bool TaskbarTopmost,
    bool AutoHide);

/// <summary>
/// Follows the primary Windows 11 taskbar so the widget can be shown as an overlay: Dejavu's own
/// unowned top-level window placed over the taskbar band, just left of the notification area.
/// Embedding into Explorer (SetParent, an owner of Shell_TrayWnd, AttachThreadInput) would tie
/// Explorer's input queue and DPI handling to Dejavu's UI thread, so this tracker only observes.
/// It never calls SetParent or changes window ownership, never injects code, and never sends or
/// posts window messages of its own to Explorer windows. Work on the dispatcher thread is limited to
/// message-free local reads (window handles, rectangles, styles, cached registry values); the one
/// synchronous shell query, SHAppBarMessage(ABM_GETSTATE), which shell32 delivers to Shell_TrayWnd as
/// WM_COPYDATA, runs on a single thread-pool worker with a timeout.
/// </summary>
internal sealed class TaskbarTracker : IDisposable
{
    private const string SettlingReason = "settling";
    private const string FullscreenReason = "fullscreen";
    private const string AutoHideReason = "autohide";
    private const string VerticalReason = "vertical";
    private const string NonXamlTaskbarReason = "non_xaml_taskbar";
    private const string TaskbarMissingReason = "taskbar_missing";
    private const string TrayMissingReason = "tray_missing";
    private const string RtlOrMirroredReason = "rtl_or_mirrored";
    private const string BandTooSmallReason = "band_too_small";
    private const string ShellMismatchReason = "shell_mismatch";
    private const string PersonalizeKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private const string AdvancedKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
    private const string WidgetsPolicyKeyPath = @"SOFTWARE\Policies\Microsoft\Dsh";
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const long WsExTopmost = 0x00000008L;
    private const long WsCaption = 0x00C00000L;
    private const long WsThickFrame = 0x00040000L;
    private const int WsPopup = unchecked((int)0x80000000);
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const int WmSettingChange = 0x001A;
    private const int WmDisplayChange = 0x007E;
    private const uint EventSystemForeground = 0x0003;
    private const uint WinEventOutOfContext = 0x0000;
    private const uint WinEventSkipOwnProcess = 0x0002;
    private const uint MonitorDefaultToNearest = 0x00000002;
    private const uint AbmGetState = 0x00000004;
    private const ulong AbsAutoHide = 0x00000001;
    // Width Explorer gives the left-aligned Widgets button next to the tray, in DIPs.
    private const double WidgetsButtonAllowance = 160;
    private const int RegistryRefreshTicks = 10;
    private const long AutoHideRefreshMilliseconds = 15_000;
    private const long AutoHideSettleLimitMilliseconds = 2_000;
    private const long SettleLimitMilliseconds = 10_000;
    // A hard fallback seen while settling must persist this long on the 250 ms cadence before it ends
    // settling: Explorer passes through these states while it rebuilds or re-lays out the taskbar.
    private const long HardFallbackConfirmMilliseconds = 2_000;
    // Environment.TickCount64 keeps counting through sleep and hibernation while the unbiased interrupt
    // time stops, so a gap between the two clocks larger than this means the PC slept.
    private const long SleepDetectionMilliseconds = 1_000;
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan SettleInterval = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan AutoHideQueryTimeout = TimeSpan.FromSeconds(2);
    private static readonly uint TaskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
    private static readonly uint CurrentProcessId = (uint)Environment.ProcessId;
    private static readonly TaskbarTrackerState InactiveState =
        new(TaskbarDockStatus.Inactive, "", null, false, false);

    private readonly Dispatcher _dispatcher;
    private readonly DispatcherTimer _timer;
    private readonly DispatcherTimer _followupShortTimer;
    private readonly DispatcherTimer _followupLongTimer;
    // Both delegates are rooted here for as long as native code may call them.
    private readonly WinEventDelegate _winEventProc;
    private readonly HwndSourceHook _windowProc;
    private HwndSource? _source;
    private nint _winEventHook;
    private nint _lastKnownTaskbar;
    private bool _enabled;
    private bool _disposed;
    private bool _foregroundQueued;
    private bool _shellChangeQueued;
    private bool _pendingSettle;
    private bool _pendingSettingChange;
    private bool _settling;
    private long _settleStartedAt;
    private TaskbarDock? _settleSample;
    private string? _settleFallbackReason;
    private long _settleFallbackSince;
    // Clock readings at the last evaluation; 0 until the first evaluation after enabling.
    private long _lastEvaluationTick;
    private ulong _lastEvaluationUnbiased;
    private int _tickCount;
    private double _systemScale = 1;
    private bool _lightTaskbar;
    private bool _leftAligned;
    private bool _widgetsButtonShown;
    private bool _autoHide;
    private bool _autoHideQueryCompleted;
    private bool _autoHideRequeryPending;
    private int _autoHideGeneration;
    private long _lastAutoHideRefreshAt;
    private Task<bool?>? _autoHideWorker;

    internal TaskbarTracker(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        _timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = PollInterval };
        _timer.Tick += OnTimerTick;
        // The short follow-up must clear the widget's 250 ms raise interval after a raise at the
        // foreground change itself, including Environment.TickCount64's ~16 ms granularity.
        _followupShortTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(300)
        };
        _followupShortTimer.Tick += OnFollowupTick;
        _followupLongTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(600)
        };
        _followupLongTimer.Tick += OnFollowupTick;
        _winEventProc = OnWinEvent;
        _windowProc = TrackerWindowProc;
    }

    internal TaskbarTrackerState State { get; private set; } = InactiveState;

    /// <summary>The current Shell_TrayWnd handle, or 0 while disabled or when none exists.</summary>
    internal nint TaskbarHandle { get; private set; }

    /// <summary>Number of times a different Shell_TrayWnd replaced the previous one (diagnostics).</summary>
    internal int RediscoveryCount { get; private set; }

    /// <summary>
    /// Raised on the dispatcher thread, only from timer, hook and window callbacks (never synchronously
    /// inside <see cref="SetEnabled"/> or <see cref="NotifyShellChanged"/>), and only when
    /// <see cref="State"/> actually changed.
    /// </summary>
    internal event EventHandler<TaskbarTrackerState>? StateChanged;

    /// <summary>
    /// Raised on the dispatcher thread while docked when the widget should verify it is still above
    /// the taskbar: "foreground", "foreground_followup" or "backstop".
    /// </summary>
    internal event EventHandler<string>? RaiseRequested;

    /// <summary>
    /// Idempotent; dispatcher thread only. Enabling starts the broadcast window, the foreground hook and
    /// the timers and sets State to Suppressed("settling") without raising StateChanged. Disabling tears
    /// everything down and sets State to Inactive without raising StateChanged.
    /// </summary>
    internal void SetEnabled(bool enabled)
    {
        if (_disposed || enabled == _enabled) return;
        if (enabled)
        {
            if (_dispatcher.HasShutdownStarted) return;
            Enable();
        }
        else Disable();
    }

    /// <summary>
    /// Re-discovers the taskbar and settles again after resume, unlock and similar shell transitions.
    /// The work is queued, so StateChanged is never raised inside this call.
    /// </summary>
    internal void NotifyShellChanged(string reason)
    {
        if (_disposed || _dispatcher.HasShutdownStarted) return;
        if (!_dispatcher.CheckAccess())
        {
            _ = _dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => NotifyShellChanged(reason)));
            return;
        }

        if (_enabled) QueueShellChange(settle: true);
    }

    public void Dispose()
    {
        if (_disposed) return;
        if (_enabled) Disable();
        _disposed = true;
        _timer.Tick -= OnTimerTick;
        _followupShortTimer.Tick -= OnFollowupTick;
        _followupLongTimer.Tick -= OnFollowupTick;
        StateChanged = null;
        RaiseRequested = null;
    }

    private void Enable()
    {
        _enabled = true;
        _tickCount = 0;
        _systemScale = ReadSystemScale();
        try
        {
            // Hidden, unowned and never shown: it exists only to receive TaskbarCreated,
            // WM_DISPLAYCHANGE and WM_SETTINGCHANGE broadcasts.
            _source = new HwndSource(new HwndSourceParameters("dejavu.TaskbarTracker")
            {
                WindowStyle = WsPopup,
                ExtendedWindowStyle = WsExToolWindow | WsExNoActivate,
                Width = 0,
                Height = 0,
                PositionX = 0,
                PositionY = 0
            });
            _source.AddHook(_windowProc);
        }
        catch
        {
            // Without the broadcast window the one-second backstop still re-evaluates the taskbar.
            _source?.Dispose();
            _source = null;
        }

        _winEventHook = SetWinEventHook(EventSystemForeground, EventSystemForeground, nint.Zero,
            _winEventProc, 0, 0, WinEventOutOfContext | WinEventSkipOwnProcess);
        BeginSettling(raise: false);
    }

    private void Disable()
    {
        _enabled = false;
        _timer.Stop();
        _followupShortTimer.Stop();
        _followupLongTimer.Stop();
        if (_winEventHook != nint.Zero)
        {
            UnhookWinEvent(_winEventHook);
            _winEventHook = nint.Zero;
        }

        if (_source is not null)
        {
            try
            {
                _source.RemoveHook(_windowProc);
                _source.Dispose();
            }
            catch
            {
                // A dispatcher that already shut down (logoff) has destroyed the window itself.
            }
            _source = null;
        }

        // A shell query still in flight belongs to the old generation and is ignored when it returns.
        _autoHideGeneration++;
        _autoHideRequeryPending = false;
        _autoHideQueryCompleted = false;
        _autoHide = false;
        _settling = false;
        _settleSample = null;
        _settleFallbackReason = null;
        _lastEvaluationTick = 0;
        _pendingSettle = false;
        _pendingSettingChange = false;
        TaskbarHandle = nint.Zero;
        State = InactiveState;
    }

    private nint TrackerWindowProc(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (_disposed || !_enabled) return nint.Zero;
        // Broadcasts are handled after this procedure returns so the broadcasting process
        // never waits for Dejavu's evaluation or widget layout.
        if (TaskbarCreatedMessage != 0 && unchecked((uint)message) == TaskbarCreatedMessage)
            QueueShellChange(settle: true);
        else if (message == WmDisplayChange) QueueShellChange(settle: true);
        else if (message == WmSettingChange) QueueShellChange(settle: false);
        return nint.Zero;
    }

    private void QueueShellChange(bool settle)
    {
        if (settle) _pendingSettle = true;
        else _pendingSettingChange = true;
        if (_shellChangeQueued || _dispatcher.HasShutdownStarted) return;
        _shellChangeQueued = true;
        _ = _dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(ProcessShellChanges));
    }

    private void ProcessShellChanges()
    {
        _shellChangeQueued = false;
        var settle = _pendingSettle;
        var settingChanged = _pendingSettingChange;
        _pendingSettle = false;
        _pendingSettingChange = false;
        if (_disposed || !_enabled) return;
        if (settle)
        {
            BeginSettling(raise: true);
            return;
        }

        if (!settingChanged) return;
        // Theme, alignment and auto-hide changes re-evaluate in place without hiding the widget.
        ReadRegistryValues();
        RefreshAutoHide();
        Refresh(sample: false);
    }

    private void OnWinEvent(nint hWinEventHook, uint eventType, nint hwnd, int idObject, int idChild,
        uint idEventThread, uint dwmsEventTime)
    {
        // Delivered inside the dispatcher's message retrieval. Only coalesce here so a burst of
        // foreground changes costs one evaluation.
        if (_disposed || !_enabled || _foregroundQueued) return;
        try
        {
            _foregroundQueued = true;
            _ = _dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(OnForegroundChanged));
        }
        catch
        {
            _foregroundQueued = false;
        }
    }

    private void OnForegroundChanged()
    {
        _foregroundQueued = false;
        if (_disposed || !_enabled) return;
        Refresh(sample: false);
        RequestRaise("foreground");
        if (_disposed || !_enabled) return;
        // Explorer reorders the taskbar and updates its fullscreen state asynchronously.
        Restart(_followupShortTimer);
        Restart(_followupLongTimer);
    }

    private void OnFollowupTick(object? sender, EventArgs e)
    {
        (sender as DispatcherTimer)?.Stop();
        if (_disposed || !_enabled) return;
        Refresh(sample: false);
        RequestRaise("foreground_followup");
    }

    private void OnTimerTick(object? sender, EventArgs e)
    {
        if (_disposed || !_enabled) return;
        var settleTick = _settling;
        if (++_tickCount % RegistryRefreshTicks == 0) ReadRegistryValues();
        if (Environment.TickCount64 - _lastAutoHideRefreshAt >= AutoHideRefreshMilliseconds) RefreshAutoHide();
        Refresh(sample: true);
        // Explorer can raise the taskbar without a foreground change this process can observe.
        if (!settleTick) RequestRaise("backstop");
    }

    private void BeginSettling(bool raise)
    {
        // This evaluation is the new baseline for sleep detection.
        _ = SleptSinceLastEvaluation();
        _settling = true;
        _settleStartedAt = Environment.TickCount64;
        _settleSample = null;
        _autoHideQueryCompleted = false;
        ReadRegistryValues();
        RefreshAutoHide();
        // Restart the cadence so the next sample is taken 250 ms after this one.
        _timer.Stop();
        _timer.Interval = SettleInterval;
        _timer.Start();
        var evaluation = Evaluate(forceDiscovery: true);
        _settleSample = evaluation.Candidate;
        // This evaluation is the first sample of the settle, for hard fallbacks as for geometry.
        _settleFallbackReason = IsHardFallback(evaluation.Reason) ? evaluation.Reason : null;
        _settleFallbackSince = _settleStartedAt;
        SetState(SettlingState(evaluation), raise);
    }

    private void EndSettling()
    {
        _settling = false;
        _settleSample = null;
        _settleFallbackReason = null;
        if (_timer.Interval != PollInterval) _timer.Interval = PollInterval;
    }

    private void Refresh(bool sample)
    {
        if (SleptSinceLastEvaluation())
        {
            // Monitors and Explorer are still being restored when the first evaluation after resume
            // runs, which can come before the controller's resume notification. Settle from here so
            // the 2 s and 10 s limits count from resume rather than from before sleep.
            BeginSettling(raise: true);
            return;
        }

        if (!_settling)
        {
            var previous = TaskbarHandle;
            if (DiscoverTaskbar(force: false) != previous)
            {
                // Explorer lost or replaced its taskbar: stay hidden while it rebuilds instead of
                // flashing the floating widget.
                BeginSettling(raise: true);
                return;
            }
        }

        var evaluation = Evaluate(forceDiscovery: false);
        if (LeavesFallback(State.Status, _settling, evaluation))
        {
            BeginSettling(raise: true);
            return;
        }

        SetState(ResolveState(evaluation, sample, Environment.TickCount64), raise: true);
    }

    /// <summary>
    /// Leaving a fallback for a dockable taskbar, including one a fullscreen window covers, settles first,
    /// so the first dock comes from two matching samples rather than from a taskbar that Explorer has only
    /// half laid out. The settle then ends in Docked or Suppressed("fullscreen") as usual.
    /// </summary>
    private static bool LeavesFallback(TaskbarDockStatus status, bool settling, Evaluation evaluation) =>
        !settling && status == TaskbarDockStatus.Fallback && evaluation.Candidate is not null;

    /// <summary>
    /// Records this evaluation's clock readings and reports whether the PC slept since the previous one.
    /// Both clocks are message-free local reads.
    /// </summary>
    private bool SleptSinceLastEvaluation()
    {
        var tick = Environment.TickCount64;
        if (!QueryUnbiasedInterruptTime(out var unbiased))
        {
            _lastEvaluationTick = 0;
            return false;
        }

        // The unbiased interrupt time counts 100 ns units.
        var slept = _lastEvaluationTick != 0 && unbiased >= _lastEvaluationUnbiased &&
                    (tick - _lastEvaluationTick) - (long)((unbiased - _lastEvaluationUnbiased) / 10_000) >
                    SleepDetectionMilliseconds;
        _lastEvaluationTick = tick;
        _lastEvaluationUnbiased = unbiased;
        return slept;
    }

    private void SetState(TaskbarTrackerState next, bool raise)
    {
        if (next == State) return;
        State = next;
        if (raise) StateChanged?.Invoke(this, next);
    }

    private void RequestRaise(string reason)
    {
        if (_disposed || !_enabled || State.Status != TaskbarDockStatus.Docked) return;
        RaiseRequested?.Invoke(this, reason);
    }

    /// <summary>
    /// Applies the settle rules to one evaluation. <paramref name="now"/> is an Environment.TickCount64
    /// reading, passed in so the layout probe can replay settle timelines without Win32 or timers.
    /// </summary>
    private TaskbarTrackerState ResolveState(Evaluation evaluation, bool sample, long now)
    {
        if (_settling)
        {
            var elapsed = now - _settleStartedAt;
            if (IsHardFallback(evaluation.Reason))
            {
                // After a display change, an Explorer restart or sign-in the taskbar can briefly keep
                // its old rectangle or lack its XAML bridge. Only a reason that repeats on consecutive
                // cadence samples for HardFallbackConfirmMilliseconds (or outlives the settle limit)
                // ends settling; a Windows 10 taskbar therefore falls back about 2 s after settling began.
                if (sample)
                {
                    if (_settleFallbackReason != evaluation.Reason)
                    {
                        _settleFallbackReason = evaluation.Reason;
                        _settleFallbackSince = now;
                    }
                    _settleSample = null;
                }
                var confirmed = sample && _settleFallbackReason == evaluation.Reason &&
                                now - _settleFallbackSince >= HardFallbackConfirmMilliseconds;
                if (!confirmed && elapsed < SettleLimitMilliseconds) return SettlingState(evaluation);
                EndSettling();
            }
            else if (evaluation.Candidate is TaskbarDock candidate)
            {
                if (sample) _settleFallbackReason = null;
                // Only the 250 ms cadence samples geometry, so two matching samples are always
                // at least that far apart.
                var stable = sample && _settleSample is TaskbarDock previous && SameGeometry(previous, candidate);
                if (sample) _settleSample = candidate;
                var autoHideReady = _autoHideQueryCompleted || elapsed >= AutoHideSettleLimitMilliseconds;
                // Geometry that never repeats must not keep the widget hidden indefinitely.
                if ((!stable && elapsed < SettleLimitMilliseconds) || !autoHideReady) return SettlingState(evaluation);
                EndSettling();
            }
            else
            {
                // The taskbar or tray may still be under construction after logon or an Explorer restart.
                if (sample)
                {
                    _settleSample = null;
                    _settleFallbackReason = null;
                }
                if (elapsed < SettleLimitMilliseconds) return SettlingState(evaluation);
                EndSettling();
            }
        }

        return evaluation.Reason switch
        {
            "" => new TaskbarTrackerState(TaskbarDockStatus.Docked, "", evaluation.Candidate,
                evaluation.TaskbarTopmost, evaluation.AutoHide),
            FullscreenReason => new TaskbarTrackerState(TaskbarDockStatus.Suppressed, FullscreenReason, null,
                evaluation.TaskbarTopmost, evaluation.AutoHide),
            _ => new TaskbarTrackerState(TaskbarDockStatus.Fallback, evaluation.Reason, null,
                evaluation.TaskbarTopmost, evaluation.AutoHide)
        };
    }

    private static TaskbarTrackerState SettlingState(Evaluation evaluation) =>
        new(TaskbarDockStatus.Suppressed, SettlingReason, null, evaluation.TaskbarTopmost, evaluation.AutoHide);

    private static bool IsHardFallback(string reason) => reason is ShellMismatchReason or NonXamlTaskbarReason
        or VerticalReason or AutoHideReason or RtlOrMirroredReason or BandTooSmallReason;

    private static bool SameGeometry(TaskbarDock left, TaskbarDock right) =>
        left.BandLeftPixels == right.BandLeftPixels && left.BandTopPixels == right.BandTopPixels &&
        left.BandRightPixels == right.BandRightPixels && left.BandBottomPixels == right.BandBottomPixels &&
        left.AnchorRightPixels == right.AnchorRightPixels;

    private nint DiscoverTaskbar(bool force)
    {
        var current = TaskbarHandle;
        if (!force && current != nint.Zero && IsWindow(current)) return current;
        var found = FindWindow("Shell_TrayWnd", null);
        if (found != nint.Zero)
        {
            if (_lastKnownTaskbar != nint.Zero && found != _lastKnownTaskbar) RediscoveryCount++;
            _lastKnownTaskbar = found;
        }

        TaskbarHandle = found;
        return found;
    }

    /// <summary>
    /// Reads the taskbar geometry with message-free local calls only. Checks run in the documented
    /// order and the first failing check names the reason.
    /// </summary>
    private Evaluation Evaluate(bool forceDiscovery)
    {
        var autoHide = _autoHide;
        var taskbar = DiscoverTaskbar(forceDiscovery);
        if (taskbar == nint.Zero) return Unavailable(TaskbarMissingReason, false, autoHide);

        var topmost = (GetWindowLongPtr(taskbar, GwlExStyle).ToInt64() & WsExTopmost) != 0;
        GetWindowThreadProcessId(taskbar, out var taskbarProcess);
        var shell = GetShellWindow();
        if (shell != nint.Zero)
        {
            GetWindowThreadProcessId(shell, out var shellProcess);
            if (shellProcess != 0 && shellProcess != taskbarProcess)
                return Unavailable(ShellMismatchReason, topmost, autoHide);
        }

        // Windows 10, ExplorerPatcher and StartAllBack taskbars have no XAML content bridge.
        if (FindWindowEx(taskbar, nint.Zero, "Windows.UI.Composition.DesktopWindowContentBridge", null) == nint.Zero)
            return Unavailable(NonXamlTaskbarReason, topmost, autoHide);

        var tray = FindWindowEx(taskbar, nint.Zero, "TrayNotifyWnd", null);
        var start = FindWindowEx(taskbar, nint.Zero, "Start", null);
        // An empty rectangle means Explorer has not laid the taskbar out yet.
        if (!GetWindowRect(taskbar, out var taskbarRect) || taskbarRect.IsEmpty)
            return Unavailable(TaskbarMissingReason, topmost, autoHide);
        RECT trayRect = default;
        RECT startRect = default;
        var hasTray = tray != nint.Zero && GetWindowRect(tray, out trayRect);
        var hasStart = start != nint.Zero && GetWindowRect(start, out startRect);

        var monitor = MonitorFromWindow(taskbar, MonitorDefaultToNearest);
        var monitorInfo = new MONITORINFO { cbSize = (uint)Marshal.SizeOf<MONITORINFO>() };
        if (monitor == nint.Zero || !GetMonitorInfo(monitor, ref monitorInfo))
            return Unavailable(TaskbarMissingReason, topmost, autoHide);
        var screen = monitorInfo.rcMonitor;

        if (taskbarRect.Width < 0.9 * screen.Width) return Unavailable(VerticalReason, topmost, autoHide);

        autoHide |= taskbarRect.Left < screen.Left || taskbarRect.Top < screen.Top ||
                    taskbarRect.Right > screen.Right || taskbarRect.Bottom > screen.Bottom;
        if (autoHide) return Unavailable(AutoHideReason, topmost, autoHide);

        var trayValid = hasTray && !trayRect.IsEmpty &&
                        trayRect.Left >= taskbarRect.Left && trayRect.Right <= taskbarRect.Right;
        // Start follows the visible band on touch devices whose taskbar window is taller.
        var bandTop = taskbarRect.Top;
        var bandBottom = taskbarRect.Bottom;
        if (hasStart && !startRect.IsEmpty &&
            startRect.Top >= taskbarRect.Top && startRect.Bottom <= taskbarRect.Bottom)
        {
            bandTop = startRect.Top;
            bandBottom = startRect.Bottom;
        }
        else if (trayValid)
        {
            bandTop = trayRect.Top;
            bandBottom = trayRect.Bottom;
        }

        if (!trayValid) return Unavailable(TrayMissingReason, topmost, autoHide);
        if (trayRect.Left + trayRect.Right < taskbarRect.Left + taskbarRect.Right)
            return Unavailable(RtlOrMirroredReason, topmost, autoHide);
        var minimumBand = (int)Math.Round(WidgetLayoutCalculator.MinimumTaskbarBandHeight * _systemScale);
        if (bandBottom - bandTop < minimumBand) return Unavailable(BandTooSmallReason, topmost, autoHide);

        var anchor = trayRect.Left;
        if (_leftAligned && _widgetsButtonShown)
            anchor -= (int)Math.Round(WidgetsButtonAllowance * _systemScale);
        // The live flag: WPF's SystemParameters.HighContrast can still be cached when this runs for the
        // same WM_SETTINGCHANGE broadcast.
        var dock = new TaskbarDock(taskbarRect.Left, bandTop, taskbarRect.Right, bandBottom, anchor,
            _lightTaskbar, ThemeManager.IsHighContrastOn());

        // Explorer drops the taskbar out of the topmost band on a monitor with a fullscreen window.
        var fullscreen = !topmost || IsForegroundFullscreen(taskbarProcess, monitor, screen);
        return new Evaluation(fullscreen ? FullscreenReason : "", dock, topmost, autoHide);
    }

    private static Evaluation Unavailable(string reason, bool topmost, bool autoHide) =>
        new(reason, null, topmost, autoHide);

    private static bool IsForegroundFullscreen(uint taskbarProcess, nint taskbarMonitor, RECT screen)
    {
        var foreground = GetForegroundWindow();
        if (foreground == nint.Zero) return false;
        GetWindowThreadProcessId(foreground, out var process);
        var ownedByShell = process != 0 && process == taskbarProcess;
        if (process == CurrentProcessId || IsShellWindowClass(foreground, ownedByShell) || IsZoomed(foreground))
            return false;
        if (MonitorFromWindow(foreground, MonitorDefaultToNearest) != taskbarMonitor) return false;

        RECT bounds;
        var style = GetWindowLongPtr(foreground, GwlStyle).ToInt64();
        if ((style & WsCaption) == WsCaption || (style & WsThickFrame) != 0)
        {
            // Framed windows count as fullscreen when their client area covers the monitor.
            if (!GetClientRect(foreground, out var client)) return false;
            var topLeft = new POINT { X = client.Left, Y = client.Top };
            var bottomRight = new POINT { X = client.Right, Y = client.Bottom };
            if (!ClientToScreen(foreground, ref topLeft) || !ClientToScreen(foreground, ref bottomRight)) return false;
            bounds = new RECT { Left = topLeft.X, Top = topLeft.Y, Right = bottomRight.X, Bottom = bottomRight.Y };
        }
        else if (!GetWindowRect(foreground, out bounds)) return false;

        return bounds.Left <= screen.Left && bounds.Top <= screen.Top &&
               bounds.Right >= screen.Right && bounds.Bottom >= screen.Bottom;
    }

    private static bool IsShellWindowClass(nint handle, bool ownedByShell)
    {
        var buffer = new System.Text.StringBuilder(256);
        if (GetClassName(handle, buffer, buffer.Capacity) <= 0) return false;
        var name = buffer.ToString();
        // Task View, Alt+Tab and Snap Assist are full-monitor XAML hosts of the taskbar's own Explorer
        // process. The class is matched only there, so a fullscreen app using it is still detected.
        return name is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd" ||
               (ownedByShell && name == "XamlExplorerHostIslandWindow");
    }

    private void ReadRegistryValues()
    {
        _lightTaskbar = ReadDword(Registry.CurrentUser, PersonalizeKeyPath, "SystemUsesLightTheme") == 1;
        // A missing TaskbarAl value means the Windows 11 default, centred.
        _leftAligned = ReadDword(Registry.CurrentUser, AdvancedKeyPath, "TaskbarAl") == 0;
        // Missing values mean the Widgets button is shown and allowed by policy.
        _widgetsButtonShown = ReadDword(Registry.CurrentUser, AdvancedKeyPath, "TaskbarDa") != 0 &&
                              ReadDword(Registry.LocalMachine, WidgetsPolicyKeyPath, "AllowNewsAndInterests") != 0;
    }

    private static int? ReadDword(RegistryKey root, string path, string name)
    {
        try
        {
            using var key = root.OpenSubKey(path);
            return key?.GetValue(name) is int value ? value : null;
        }
        catch
        {
            return null;
        }
    }

    private static double ReadSystemScale()
    {
        try
        {
            var dpi = GetDpiForSystem();
            return dpi == 0 ? 1 : dpi / 96.0;
        }
        catch (EntryPointNotFoundException)
        {
            // GetDpiForSystem needs Windows 10 1607; those shells never dock anyway.
            return 1;
        }
    }

    private void RefreshAutoHide()
    {
        if (_disposed || !_enabled) return;
        _lastAutoHideRefreshAt = Environment.TickCount64;
        // Every refresh makes earlier results stale. A query still blocked inside a busy Explorer is
        // not joined by another thread-pool worker; it is repeated once that worker returns.
        var generation = ++_autoHideGeneration;
        if (_autoHideWorker is { IsCompleted: false })
        {
            _autoHideRequeryPending = true;
            return;
        }

        var worker = Task.Run(() => QueryAutoHideState());
        _autoHideWorker = worker;
        _ = ObserveAutoHideQueryAsync(worker, generation);
    }

    private async Task ObserveAutoHideQueryAsync(Task<bool?> worker, int generation)
    {
        bool? autoHide = null;
        var timedOut = false;
        try
        {
            autoHide = await worker.WaitAsync(AutoHideQueryTimeout).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            // A timeout keeps the last known value; the geometric check still detects a hidden taskbar.
            timedOut = true;
        }
        catch
        {
            // A failed query also keeps the last known value.
        }

        PostToDispatcher(() => OnAutoHideQueryCompleted(generation, autoHide));
        if (!timedOut) return;

        // The blocked call still owns the only worker slot. Once Explorer answers, run the
        // re-query that refreshes requested while it was blocked.
        try
        {
            await worker.ConfigureAwait(false);
        }
        catch
        {
            // QueryAutoHideState reports failures as null; the release below runs either way.
        }
        PostToDispatcher(OnAutoHideWorkerReleased);
    }

    private void PostToDispatcher(Action action)
    {
        try
        {
            if (_disposed || _dispatcher.HasShutdownStarted) return;
            _ = _dispatcher.BeginInvoke(DispatcherPriority.Normal, action);
        }
        catch
        {
            // The dispatcher is shutting down and no longer needs the result.
        }
    }

    private void OnAutoHideWorkerReleased()
    {
        if (_disposed || !_enabled || !_autoHideRequeryPending) return;
        _autoHideRequeryPending = false;
        RefreshAutoHide();
    }

    private void OnAutoHideQueryCompleted(int generation, bool? autoHide)
    {
        if (_disposed || !_enabled) return;
        if (generation != _autoHideGeneration)
        {
            // Stale after a disable, an Explorer restart or a newer refresh.
            if (_autoHideRequeryPending && _autoHideWorker is not { IsCompleted: false })
            {
                _autoHideRequeryPending = false;
                RefreshAutoHide();
            }
            return;
        }

        if (autoHide is bool value) _autoHide = value;
        _autoHideQueryCompleted = true;
        Refresh(sample: false);
    }

    private static bool? QueryAutoHideState()
    {
        try
        {
            var data = new APPBARDATA { cbSize = (uint)Marshal.SizeOf<APPBARDATA>() };
            var state = SHAppBarMessage(AbmGetState, ref data);
            return ((ulong)state & AbsAutoHide) != 0;
        }
        catch
        {
            return null;
        }
    }

    private static void Restart(DispatcherTimer timer)
    {
        timer.Stop();
        timer.Start();
    }

    private readonly record struct Evaluation(
        string Reason,           // "" when dockable, FullscreenReason when dockable but covered, else a fallback
        TaskbarDock? Candidate,  // non-null for "" and FullscreenReason
        bool TaskbarTopmost,
        bool AutoHide);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public readonly int Width => Right - Left;
        public readonly bool IsEmpty => Right <= Left || Bottom <= Top;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public uint cbSize;
        public nint hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public nint lParam;
    }

    private delegate void WinEventDelegate(nint hWinEventHook, uint eventType, nint hwnd, int idObject,
        int idChild, uint idEventThread, uint dwmsEventTime);

    [DllImport("user32.dll", EntryPoint = "FindWindowW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint FindWindow(string? className, string? windowName);

    [DllImport("user32.dll", EntryPoint = "FindWindowExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint FindWindowEx(nint parent, nint childAfter, string? className, string? windowName);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint handle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint GetShellWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(nint handle, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint handle, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(nint handle, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ClientToScreen(nint handle, ref POINT point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint MonitorFromWindow(nint handle, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MONITORINFO info);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint handle, int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetClassName(nint handle, System.Text.StringBuilder className, int maxCount);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsZoomed(nint handle);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetDpiForSystem();

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryUnbiasedInterruptTime(out ulong unbiasedTime);

    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern uint RegisterWindowMessage(string message);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWinEventHook(uint eventMin, uint eventMax, nint module,
        WinEventDelegate callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(nint hook);

    [DllImport("shell32.dll")]
    private static extern nuint SHAppBarMessage(uint message, ref APPBARDATA data);
}
