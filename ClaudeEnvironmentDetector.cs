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

        Process.Start(new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        });
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

        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            yield return Path.Combine(directory, "claude.exe");
            yield return Path.Combine(directory, "claude.cmd");
        }
    }
}
