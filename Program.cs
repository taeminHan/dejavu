namespace ClaudeUsageTray;

using Velopack;

internal static class Program
{
    private const string MutexName = "Local\\dejavu.SingleInstance";
    private const string ActivationEventName = "Local\\dejavu.ShowSettings";

    [STAThread]
    private static void Main()
    {
        try
        {
            VelopackApp.Build()
                .OnBeforeUninstallFastCallback(_ => DesktopApplicationController.PerformUninstallCleanup())
                .Run();
            using var mutex = new Mutex(true, MutexName, out var createdNew);
            if (!createdNew)
            {
                try
                {
                    using var activationEvent = EventWaitHandle.OpenExisting(ActivationEventName);
                    activationEvent.Set();
                }
                catch (WaitHandleCannotBeOpenedException) { }
                return;
            }

            using var showSettingsEvent = new EventWaitHandle(
                false, EventResetMode.AutoReset, ActivationEventName);

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
            var startWithDetails = Environment.GetCommandLineArgs()
                .Any(argument => string.Equals(argument, "--details", StringComparison.OrdinalIgnoreCase));
            var previewTheme = ParsePreview<WidgetVisualTheme>("theme");
            var previewDensity = ParsePreview<WidgetDensity>("density");
            var previewLayout = ParsePreview<WidgetLayout>("layout");
            var previewServices = ParsePreview<ServiceDisplayMode>("services");
            using var controller = new DesktopApplicationController(
                application, startWithSettings, startWithOnboarding, startWithDetails,
                previewTheme, previewDensity, previewLayout, previewServices);
            var activationRegistration = ThreadPool.RegisterWaitForSingleObject(
                showSettingsEvent,
                (_, _) => application.Dispatcher.BeginInvoke(controller.ShowSettingsFromExternalActivation),
                null,
                Timeout.Infinite,
                executeOnlyOnce: false);
            try
            {
                application.Run();
            }
            finally
            {
                activationRegistration.Unregister(null);
            }
        }
        catch (Exception exception)
        {
            WriteCrash(exception);
        }
    }

    private static T? ParsePreview<T>(string option) where T : struct, Enum
    {
        var prefix = $"--{option}=";
        return Environment.GetCommandLineArgs()
            .Select(argument => argument.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                ? argument[prefix.Length..] : null)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => Enum.TryParse<T>(value, true, out var parsed) ? parsed : (T?)null)
            .FirstOrDefault(value => value is not null);
    }

    private static void WriteCrash(Exception exception)
    {
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "crash.log");
            if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024)
                File.Move(path, Path.Combine(directory, "crash.previous.log"), true);
            File.AppendAllText(path,
                $"[{DateTimeOffset.Now:O}] dejavu {VelopackUpdateService.CurrentVersion}\n{exception}\n\n");
        }
        catch { }
    }
}
