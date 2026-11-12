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
    private const string ConfigDirectoryVariable = "CLAUDE_CONFIG_DIR";

    public static ClaudeEnvironment Detect() => new(FindExecutable(), FindCredentialPath());

    public static string? FindCredentialPath()
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DEJAVU_CLAUDE_SOURCE"), "desktop",
                StringComparison.OrdinalIgnoreCase)) return null;

        var path = ResolveCredentialPath(Environment.GetEnvironmentVariable(ConfigDirectoryVariable),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        return path is not null && File.Exists(path) ? path : null;
    }

    // An updater or startup process can inherit an environment from before the user set this
    // override. Recover only the directory setting, so the reader and an explicit login use
    // the same profile. This changes neither the registry nor Claude's files.
    internal static void RestorePersistedProfileOverride()
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable(ConfigDirectoryVariable) is not null)
            return;
        try
        {
            var configured = Environment.GetEnvironmentVariable(ConfigDirectoryVariable, EnvironmentVariableTarget.User)
                             ?? Environment.GetEnvironmentVariable(ConfigDirectoryVariable, EnvironmentVariableTarget.Machine);
            if (!string.IsNullOrWhiteSpace(configured))
                Environment.SetEnvironmentVariable(ConfigDirectoryVariable, configured, EnvironmentVariableTarget.Process);
        }
        catch (System.Security.SecurityException) { }
    }

    internal static string? ResolveCredentialPath(string? configured, string userProfile)
    {
        if (!string.IsNullOrWhiteSpace(configured))
            return Path.IsPathFullyQualified(configured) ? Path.Combine(configured, ".credentials.json") : null;
        return Path.IsPathFullyQualified(userProfile) ? Path.Combine(userProfile, ".claude", ".credentials.json") : null;
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
