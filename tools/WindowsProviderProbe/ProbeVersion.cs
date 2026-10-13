namespace ClaudeUsageTray;

// Only initialize's client metadata depends on the updater. The updater, app/controller, WPF,
// real provider discovery and all persisted user data stay outside this synthetic executable.
internal static class VelopackUpdateService
{
    internal const string CurrentVersion = "provider-probe";
}
