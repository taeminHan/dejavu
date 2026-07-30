using System.ComponentModel;
using System.Windows;
using System.Windows.Input;

namespace ClaudeUsageTray;

public partial class UpdateWindow : Window
{
    private bool _busy;

    internal UpdateWindow() => InitializeComponent();

    internal event EventHandler? InstallRequested;

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
            message ?? "새 업데이트가 공개되면 앱을 시작할 때 한 번 확인해서 알려드릴게요.");
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
        e.Cancel = true;
        if (!_busy) Hide();
    }
}
