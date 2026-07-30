using System.Reflection;
using Velopack;
using Velopack.Sources;

namespace ClaudeUsageTray;

internal sealed class VelopackUpdateService
{
    private const string RepositoryUrl = "https://github.com/taeminHan/dejavu";
    private readonly UpdateManager _manager;

    internal VelopackUpdateService()
    {
        var includePrereleases = CurrentVersion.Contains('-', StringComparison.Ordinal);
        _manager = new UpdateManager(
            new GithubSource(RepositoryUrl, null, includePrereleases, downloader: null),
            new UpdateOptions(), locator: null);
    }

    internal bool IsInstalled => _manager.IsInstalled;

    internal static string CurrentVersion =>
        (Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion ?? "0.0.0").Split('+')[0];

    internal Task<UpdateInfo?> CheckAsync() => _manager.CheckForUpdatesAsync();

    internal Task DownloadAsync(UpdateInfo update, Action<int> progress, CancellationToken cancellationToken) =>
        _manager.DownloadUpdatesAsync(update, progress, cancellationToken);

    internal void ApplyAndRestart(UpdateInfo update) =>
        _manager.ApplyUpdatesAndRestart(update.TargetFullRelease, []);
}
