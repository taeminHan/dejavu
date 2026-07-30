using System.Diagnostics;

namespace ClaudeUsageTray;

internal sealed record ClaudeEnvironment(string? ExecutablePath, string? CredentialPath)
{
    public bool IsInstalled => ExecutablePath is not null;
    public bool IsLoggedIn => CredentialPath is not null;
}

internal static class ClaudeEnvironmentDetector
{
    private const string SetupUrl = "https://docs.anthropic.com/en/docs/claude-code/getting-started";

    public static ClaudeEnvironment Detect() => new(FindExecutable(), FindCredentialPath());

    public static string? FindCredentialPath()
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DEJAVU_CLAUDE_SOURCE"), "desktop",
                StringComparison.OrdinalIgnoreCase)) return null;

        foreach (var path in CredentialCandidates())
        {
            try
            {
                if (File.Exists(path) && new FileInfo(path).Length > 0) return path;
            }
            catch { }
        }
        return null;
    }

    public static string? FindExecutable()
    {
        foreach (var path in ExecutableCandidates().Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                if (File.Exists(path)) return path;
            }
            catch { }
        }
        return null;
    }

    public static bool OpenLogin()
    {
        var executable = FindExecutable();
        if (executable is null)
        {
            OpenSetupPage();
            return false;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        startInfo.ArgumentList.Add("auth");
        startInfo.ArgumentList.Add("login");
        Process.Start(startInfo);
        return true;
    }

    public static void OpenSetupPage() => Process.Start(new ProcessStartInfo(SetupUrl) { UseShellExecute = true });

    private static IEnumerable<string> CredentialCandidates()
    {
        var configured = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
        if (!string.IsNullOrWhiteSpace(configured)) yield return Path.Combine(configured, ".credentials.json");

        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        yield return Path.Combine(profile, ".claude", ".credentials.json");
    }

    private static IEnumerable<string> ExecutableCandidates()
    {
        var explicitPath = Environment.GetEnvironmentVariable("CLAUDE_CODE_PATH");
        if (!string.IsNullOrWhiteSpace(explicitPath)) yield return explicitPath;

        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        yield return Path.Combine(profile, ".local", "bin", "claude.exe");
        yield return Path.Combine(appData, "npm", "claude.cmd");
        yield return Path.Combine(appData, "npm", "claude.exe");
        foreach (var bundled in DesktopBundledExecutables(appData)) yield return bundled;

        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            yield return Path.Combine(directory, "claude.exe");
            yield return Path.Combine(directory, "claude.cmd");
        }
    }

    private static IEnumerable<string> DesktopBundledExecutables(string appData)
    {
        var root = Path.Combine(appData, "Claude", "claude-code");
        string[] directories;
        try { directories = Directory.GetDirectories(root); }
        catch { yield break; }

        foreach (var directory in directories.OrderByDescending(path => path, StringComparer.OrdinalIgnoreCase))
            yield return Path.Combine(directory, "claude.exe");
    }
}
