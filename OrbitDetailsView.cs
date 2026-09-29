using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;

namespace ClaudeUsageTray;

/// <summary>
/// Details-only composition: one chart, separately named provider legends.
/// The floating widget keeps its independent provider systems and sizing rules.
/// </summary>
public sealed class OrbitDetailsView : Border
{
    internal void Update(ApplicationState state, TraySettings settings)
    {
        SetResourceReference(StyleProperty, "OrbitSystemCard");
        var (claude, codex) = settings.ResolveServices(state);
        var claudeMetrics = claude ? OrbitMetric.Claude(state) : [];
        var codexMetrics = codex ? OrbitMetric.Codex(state, true) : [];
        var combined = claudeMetrics.Concat(codexMetrics).ToArray();
        var content = new StackPanel();
        Child = content;
        if (combined.Length == 0) return;

        if (settings.ShowProgressBars)
        {
            var chartSize = claude && codex ? 260d : 224d;
            var chart = new OrbitSystemChart(combined, settings.UseThresholdColors, widget: false, solar: true)
            {
                Width = chartSize, Height = chartSize,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 16)
            };
            AutomationProperties.SetName(chart, "사용량 태양계. 수치는 아래 서비스별 목록에 표시됩니다.");
            content.Children.Add(chart);
            var separator = new Border { Height = 1, Margin = new Thickness(0, 0, 0, 16) };
            separator.SetResourceReference(BackgroundProperty, "BorderBrush");
            content.Children.Add(separator);
        }

        var legends = new Grid();
        legends.ColumnDefinitions.Add(new ColumnDefinition());
        if (claude && codex)
        {
            legends.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(25) });
            legends.ColumnDefinitions.Add(new ColumnDefinition());
            var divider = new Border { Width = 1, HorizontalAlignment = System.Windows.HorizontalAlignment.Center };
            divider.SetResourceReference(BackgroundProperty, "BorderBrush");
            Grid.SetColumn(divider, 1);
            legends.Children.Add(divider);
        }
        if (claude) legends.Children.Add(Provider("Claude", state.ClaudeMessage, claudeMetrics, settings));
        if (codex)
        {
            var provider = Provider("Codex", state.CodexMessage, codexMetrics, settings);
            Grid.SetColumn(provider, claude ? 2 : 0);
            var credits = new Border { Padding = new Thickness(10, 8, 10, 8), Margin = new Thickness(0, 4, 0, 0),
                CornerRadius = new CornerRadius(12), BorderThickness = new Thickness(1) };
            credits.SetResourceReference(BackgroundProperty, "SurfaceBrush");
            credits.SetResourceReference(BorderBrushProperty, "BorderBrush");
            var text = new StackPanel();
            text.Children.Add(Label("초기화권", 10, "OrbitLegendText"));
            text.Children.Add(Label(state.CodexSnapshot?.ResetCredits is int count ? $"{count}개" : "--개",
                12, "OrbitValueText"));
            var expiry = state.CodexSnapshot?.ResetCreditsExpireAt is DateTimeOffset time
                ? $"가장 빠른 만료 {time.LocalDateTime:M월 d일 HH:mm}" : "읽기 전용";
            text.Children.Add(Label(expiry, 10, "OrbitLegendText"));
            credits.Child = text;
            provider.Children.Add(credits);
            legends.Children.Add(provider);
        }
        content.Children.Add(legends);
    }

    private static StackPanel Provider(string title, string status, OrbitMetric[] metrics, TraySettings settings)
    {
        var panel = new StackPanel();
        var header = new Grid { Margin = new Thickness(0, 0, 0, 12) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.Children.Add(Label(title, 14, "OrbitProviderText"));
        var state = Label(status, 10, "OrbitLegendText");
        state.Margin = new Thickness(8, 0, 0, 0);
        state.VerticalAlignment = VerticalAlignment.Center;
        state.TextAlignment = TextAlignment.Right;
        Grid.SetColumn(state, 1);
        state.TextWrapping = TextWrapping.NoWrap;
        state.TextTrimming = TextTrimming.CharacterEllipsis;
        state.ToolTip = status;
        header.Children.Add(state);
        panel.Children.Add(header);
        var legend = new OrbitSystemView();
        legend.Update(metrics, title, settings, detailed: true, legendOnly: true);
        panel.Children.Add(legend);
        return panel;
    }

    private static TextBlock Label(string text, double size, string style)
    {
        var label = new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap };
        label.SetResourceReference(StyleProperty, style);
        label.SetResourceReference(TextBlock.FontFamilyProperty, "AppFontFamily");
        return label;
    }
}
