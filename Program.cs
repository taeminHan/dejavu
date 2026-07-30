namespace ClaudeUsageTray;

using Velopack;

internal static class Program
{
    private const string MutexName = "Local\\dejavu.SingleInstance";

    [STAThread]
    private static void Main()
    {
        try
        {
            VelopackApp.Build()
                .OnBeforeUninstallFastCallback(_ => DesktopApplicationController.PerformUninstallCleanup())
                .Run();
            using var mutex = new Mutex(true, MutexName, out var createdNew);
            if (!createdNew) return;

            var application = new System.Windows.Application
            {
                ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown
            };
            application.DispatcherUnhandledException += (_, args) => WriteCrash(args.Exception);
            AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            {
                if (args.ExceptionObject is Exception exception) WriteCrash(exception);
            };
            application.Resources.MergedDictionaries.Add(new System.Windows.ResourceDictionary
            {
                Source = new Uri("/dejavu;component/ThemeResources.xaml", UriKind.Relative)
            });

            var startWithSettings = Environment.GetCommandLineArgs()
                .Any(argument => string.Equals(argument, "--settings", StringComparison.OrdinalIgnoreCase));
            var startWithOnboarding = Environment.GetCommandLineArgs()
                .Any(argument => string.Equals(argument, "--onboarding", StringComparison.OrdinalIgnoreCase));
            using var controller = new DesktopApplicationController(application, startWithSettings, startWithOnboarding);
            application.Run();
        }
        catch (Exception exception)
        {
            WriteCrash(exception);
        }
    }

    private static void WriteCrash(Exception exception)
    {
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory, "crash.log"),
                $"{DateTimeOffset.Now:O}\n{exception}");
        }
        catch { }
    }
}
