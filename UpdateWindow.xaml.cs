using System.ComponentModel;
using System.Windows;
using System.Windows.Input;

namespace ClaudeUsageTray;

public partial class UpdateWindow : Window
{
    private bool _busy;
    internal bool AllowClose { get; set; }

    internal UpdateWindow() => InitializeComponent();

    internal event EventHandler? InstallRequested;

    internal void ApplyTheme(WidgetVisualTheme theme)
    {
        DownloadProgress.Style = FindResource(ThemeManager.WidgetProgressStyleKey(theme))
            as System.Windows.Style;
        UpdateTitleRow.Height = new GridLength(54);
        UpdateTitleBar.BorderThickness = new Thickness(0, 0, 0, 1);
        UpdateTitleBar.Background = System.Windows.Media.Brushes.Transparent;
        UpdateThemeBadge.Width = UpdateThemeBadge.Height = 28;
        UpdateThemeBadge.CornerRadius = FindResource("BadgeCornerRadius") is CornerRadius badgeRadius
            ? badgeRadius : new CornerRadius(0);
        UpdateContent.Margin = new Thickness(26, 24, 26, 22);
        UpdateNotesCard.CornerRadius = FindResource("CardCornerRadius") is CornerRadius cardRadius
            ? cardRadius : new CornerRadius(0);
        UpdateNotesCard.BorderThickness = new Thickness(1);
        UpdateNotesCard.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "BackgroundBrush");
        UpdateBrandText.Text = "dejavu 업데이트";

        switch (theme)
        {
            case WidgetVisualTheme.RetroNight:
                UpdateTitleRow.Height = new GridLength(48);
                UpdateTitleBar.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "RaisedSurfaceBrush");
                UpdateThemeBadge.CornerRadius = new CornerRadius(0);
                UpdateBrandText.Text = "DEJAVU // UPDATE";
                UpdateContent.Margin = new Thickness(20, 18, 20, 18);
                UpdateNotesCard.CornerRadius = new CornerRadius(0);
                UpdateNotesCard.BorderThickness = new Thickness(2);
                break;
            case WidgetVisualTheme.FluentGlass:
                UpdateTitleRow.Height = new GridLength(60);
                UpdateTitleBar.BorderThickness = new Thickness(0);
                UpdateThemeBadge.Width = UpdateThemeBadge.Height = 34;
                UpdateBrandText.Text = "dejavu glass · update";
                UpdateContent.Margin = new Thickness(28, 24, 28, 24);
                UpdateNotesCard.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "RaisedSurfaceBrush");
                break;
            case WidgetVisualTheme.TerminalMono:
                UpdateTitleRow.Height = new GridLength(46);
                UpdateTitleBar.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "RaisedSurfaceBrush");
                UpdateThemeBadge.Width = 40;
                UpdateThemeBadge.Height = 26;
                UpdateThemeBadge.CornerRadius = new CornerRadius(0);
                UpdateBrandText.Text = "dejavu.update --check";
                UpdateContent.Margin = new Thickness(18, 16, 18, 16);
                UpdateNotesCard.CornerRadius = new CornerRadius(0);
                break;
            case WidgetVisualTheme.Orbit:
                UpdateTitleRow.Height = new GridLength(62);
                UpdateTitleBar.BorderThickness = new Thickness(0);
                UpdateThemeBadge.Width = UpdateThemeBadge.Height = 38;
                UpdateThemeBadge.CornerRadius = new CornerRadius(19);
                UpdateBrandText.Text = "DEJAVU ORBIT · UPDATE";
                UpdateNotesCard.CornerRadius = new CornerRadius(18);
                UpdateNotesCard.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "RaisedSurfaceBrush");
                break;
            case WidgetVisualTheme.PaperInk:
                UpdateTitleRow.Height = new GridLength(50);
                UpdateThemeBadge.Width = 24;
                UpdateThemeBadge.Height = 32;
                UpdateThemeBadge.CornerRadius = new CornerRadius(0);
                UpdateBrandText.Text = "dejavu 갱신 기록";
                UpdateContent.Margin = new Thickness(30, 22, 30, 20);
                UpdateNotesCard.CornerRadius = new CornerRadius(0);
                UpdateNotesCard.BorderThickness = new Thickness(2, 0, 0, 0);
                UpdateNotesCard.Background = System.Windows.Media.Brushes.Transparent;
                break;
        }
    }

    internal void ShowAvailable(string latestVersion, string? releaseNotes)
    {
        ResetControls();
        TitleText.Text = "새 버전을 사용할 수 있어요";
        VersionText.Text = $"현재 {VelopackUpdateService.CurrentVersion}  →  최신 {latestVersion}";
        NotesText.Text = string.IsNullOrWhiteSpace(releaseNotes)
            ? "최신 기능과 안정성 개선이 포함되어 있습니다." : releaseNotes.Trim();
        ShowAndActivate();
    }

    internal void ShowCurrent(string? message = null)
    {
        ShowStatus("최신 버전을 사용 중이에요",
            message ?? "새 업데이트가 공개되면 앱 시작 후와 매 정각 자동으로 확인해서 알려드릴게요.");
    }

    internal void ShowStatus(string title, string message)
    {
        ResetControls();
        TitleText.Text = title;
        VersionText.Text = $"dejavu {VelopackUpdateService.CurrentVersion}";
        NotesText.Text = message;
        InstallButton.Content = "확인";
        InstallButton.Tag = "close";
        LaterButton.Visibility = Visibility.Collapsed;
        ShowAndActivate();
    }

    internal void SetDownloading(int percent)
    {
        _busy = true;
        ProgressPanel.Visibility = Visibility.Visible;
        DownloadProgress.Value = Math.Clamp(percent, 0, 100);
        ProgressText.Text = $"{percent}%";
        StatusText.Text = percent >= 100 ? "업데이트 준비 중" : "업데이트 다운로드 중";
        InstallButton.IsEnabled = false;
        LaterButton.IsEnabled = false;
        CloseButton.IsEnabled = false;
    }

    internal void SetError(string message)
    {
        _busy = false;
        ProgressPanel.Visibility = Visibility.Visible;
        DownloadProgress.Value = 0;
        ProgressText.Text = "";
        StatusText.Text = message;
        InstallButton.Content = "다시 시도";
        InstallButton.Tag = null;
        InstallButton.IsEnabled = true;
        LaterButton.Visibility = Visibility.Visible;
        LaterButton.IsEnabled = true;
        CloseButton.IsEnabled = true;
    }

    private void ResetControls()
    {
        _busy = false;
        ProgressPanel.Visibility = Visibility.Collapsed;
        InstallButton.Content = "지금 업데이트";
        InstallButton.Tag = null;
        InstallButton.IsEnabled = true;
        LaterButton.Visibility = Visibility.Visible;
        LaterButton.IsEnabled = true;
        CloseButton.IsEnabled = true;
    }

    private void ShowAndActivate()
    {
        if (!IsVisible) Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true;
        Topmost = false;
        Focus();
    }

    private void OnInstallClick(object sender, RoutedEventArgs e)
    {
        if (Equals(InstallButton.Tag, "close")) Hide();
        else InstallRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnLaterClick(object sender, RoutedEventArgs e)
    {
        if (!_busy) Hide();
    }

    private void OnTitleBarMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        try { DragMove(); } catch (InvalidOperationException) { }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (AllowClose) return;
        e.Cancel = true;
        if (!_busy) Hide();
    }
}
