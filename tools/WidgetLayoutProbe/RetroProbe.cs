using System.Globalization;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

internal static partial class Program
{
    // Synthetic real-WPF trees: no controller, authentication, provider requests or settings writes.
    private static int RunRetroProbe(Assembly assembly, StateFactory factory)
    {
        var failures = new List<string>();
        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var widgetType = RequiredType(assembly, "ClaudeUsageTray.UsageWidgetWindow");
        var detailsType = RequiredType(assembly, "ClaudeUsageTray.UsageDetailsWindow");
        var apply = RequiredType(assembly, "ClaudeUsageTray.ThemeManager").GetMethod("Apply")!;
        var preview = Environment.GetEnvironmentVariable("DEJAVU_RETRO_PREVIEW");
        if (!string.IsNullOrEmpty(preview)) Directory.CreateDirectory(preview);
        // Loading the compiled resource catches corrupt fonts and packaging/fallback mistakes.
        var font = new GlyphTypeface(new Uri("pack://application:,,,/dejavu;component/Assets/Fonts/DejavuPixel-Regular.ttf"));
        if (!font.FamilyNames.Values.Contains("Dejavu Pixel") || !"0123456789%FABLECodex".All(c => font.CharacterToGlyphMap.ContainsKey(c)))
            failures.Add("bundled bitmap font family/glyphs");
        var count = 0;
        foreach (var appearance in new[] { "Light", "Dark" })
        foreach (var density in new[] { "Small", "Compact", "Comfortable" })
        foreach (var rows in new[] { "SingleRow", "TwoRows" })
        foreach (var progress in new[] { false, true })
        foreach (var service in new[] { "ClaudeOnly", "CodexOnly", "ClaudeAndCodex" })
        foreach (var unknown in new[] { false, true })
        {
            var settings = Activator.CreateInstance(settingsType)!;
            void Option(string key, string value) => Set(settingsType, settings, key,
                Enum.Parse(settingsType.GetProperty(key)!.PropertyType, value));
            Option("WidgetTheme", "RetroNight"); Option("Theme", appearance);
            Option("WidgetDensity", density); Option("WidgetLayout", rows); Option("ServiceDisplayMode", service);
            Set(settingsType, settings, "ShowProgressBars", progress);
            apply.Invoke(null, [settings]);
            var state = factory.Create(service != "CodexOnly", service != "ClaudeOnly");
            var limit = RequiredType(assembly, "ClaudeUsageTray.UsageLimit");
            void Reading(object snapshot, string property, double n) => snapshot.GetType().GetProperty(property)!
                .SetValue(snapshot, unknown ? null : Activator.CreateInstance(limit, [n, DateTimeOffset.Now.AddHours(2)]));
            if (Get(state, "Snapshot") is object claude)
            {
                Reading(claude, "FiveHour", 24);
                Reading(claude, "Weekly", 71);
                Reading(claude, "Fable", 92);
                Set(claude.GetType(), claude, "FableExpired", unknown);
            }
            if (Get(state, "CodexSnapshot") is object codex)
            {
                Reading(codex, "FiveHour", 0);
                Reading(codex, "Weekly", 100);
            }
            Set(state.GetType(), state, "Message", "Claude · Codex 사용량이 최신 상태입니다");
            Set(state.GetType(), state, "ClaudeMessage", "Claude 최신");
            Set(state.GetType(), state, "CodexMessage", "Codex 최신");
            Set(state.GetType(), state, "UpdatedAt", DateTimeOffset.Now);
            var prefix = $"{appearance}/{density}/{rows}/{progress}/{service}/{unknown}";
            var widget = (Window)Activator.CreateInstance(widgetType, BindingFlags.Instance | BindingFlags.NonPublic,
                null, [settings], null)!;
            widgetType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(widget, [state]);
            var card = RequiredElement<FrameworkElement>(widget, "WidgetCard");
            ArrangeRetro(card, widget.Width, widget.Height);
            if (card.DesiredSize.Height > widget.Height + .5) failures.Add(prefix + ": widget height");
            CheckRetroText(card, prefix, failures);
            if (RequiredElement<FrameworkElement>(widget, "ThemeTextureOverlay").Visibility != Visibility.Collapsed)
                failures.Add(prefix + ": decorative scanlines survived");
            foreach (var metric in new[] { "FiveHour", "Weekly", "Fable", "CodexFive", "Codex" })
            {
                var ring = RequiredElement<FrameworkElement>(widget, "Retro" + metric + "Ring");
                if ((ring.Visibility == Visibility.Visible) != progress) failures.Add(prefix + ": pixel ring visibility");
                var smooth = RequiredElement<FrameworkElement>(widget, "Small" + metric + "Track");
                if (smooth.Visibility != Visibility.Collapsed) failures.Add(prefix + ": smooth circle survived");
            }
            foreach (var text in Descendants(card).OfType<TextBlock>().Where(t => t.Text.EndsWith('%')))
            {
                if (Get<bool>(text, "UsesPixels") != true || TextOptions.GetTextRenderingMode(text) != TextRenderingMode.Aliased)
                    failures.Add(prefix + ": value is not rendered as pixels");
                // Composite-family resolution must use the bundled advance width, not Consolas fallback.
                var measured = new FormattedText(text.Text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                    new Typeface(text.FontFamily, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal),
                    text.FontSize, text.Foreground, VisualTreeHelper.GetDpi(text).PixelsPerDip);
                if (Math.Abs(measured.WidthIncludingTrailingWhitespace - text.Text.Length * .6 * text.FontSize) > .05)
                    failures.Add(prefix + ": bundled font fallback " + text.Text + " width=" + measured.WidthIncludingTrailingWhitespace);
            }
            var details = (Window)Activator.CreateInstance(detailsType, nonPublic: true)!;
            detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(details, [state, settings]);
            var detailCard = RequiredElement<FrameworkElement>(details, "DetailsCard");
            detailCard.Measure(new Size(details.Width, double.PositiveInfinity));
            ArrangeRetro(detailCard, details.Width, Math.Min(details.MaxHeight, detailCard.DesiredSize.Height));
            CheckRetroText(detailCard, prefix + "/details", failures);
            if (RequiredElement<Border>(details, "DetailsCard").CornerRadius != new CornerRadius(0))
                failures.Add(prefix + ": rounded detail card");
            if (!string.IsNullOrEmpty(preview) && appearance == "Dark" && service == "ClaudeAndCodex" && progress && !unknown)
            {
                RenderOrbit(card, Path.Combine(preview, $"widget-{density}-{rows}.png"));
                if (density == "Comfortable" && rows == "SingleRow") RenderOrbit(detailCard, Path.Combine(preview, "details.png"));
            }
            // Switching themes on existing instances must remove the pixel-only chrome and glyph treatment.
            Option("WidgetTheme", "Modern"); apply.Invoke(null, [settings]);
            widgetType.GetMethod("ApplySettings", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(widget, [settings]);
            detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(details, [state, settings]);
            if (RequiredElement<FrameworkElement>(widget, "RetroWidgetFrame").Visibility != Visibility.Collapsed ||
                RequiredElement<FrameworkElement>(details, "RetroDetailsFrame").Visibility != Visibility.Collapsed ||
                Get<bool>(RequiredElement<TextBlock>(widget, "CompactFiveHourValue"), "PixelEnabled"))
                failures.Add(prefix + ": pixels leaked into Modern");
            CloseWidget(widget); details.Close(); count++;
        }
        foreach (var failure in failures) Console.Error.WriteLine("RETRO " + failure);
        Console.WriteLine($"Retro pixel matrix: {count} widget/detail states, {failures.Count} failures");
        return failures.Count;
    }

    private static void ArrangeRetro(FrameworkElement card, double width, double height)
    {
        card.Measure(new Size(width, double.PositiveInfinity));
        card.Arrange(new Rect(0, 0, width, height)); card.UpdateLayout();
    }

    private static void CheckRetroText(FrameworkElement card, string prefix, List<string> failures)
    {
        foreach (var text in Descendants(card).OfType<TextBlock>())
        {
            if (text.TextWrapping != TextWrapping.NoWrap || text.TextTrimming != TextTrimming.None) continue;
            var measured = new FormattedText(text.Text, CultureInfo.CurrentCulture, text.FlowDirection,
                new Typeface(text.FontFamily, text.FontStyle, text.FontWeight, text.FontStretch), text.FontSize,
                text.Foreground, VisualTreeHelper.GetDpi(text).PixelsPerDip);
            if (measured.Width > text.ActualWidth + 1) failures.Add(prefix + ": clipped " + text.Text);
        }
    }
}
