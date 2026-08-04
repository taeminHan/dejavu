using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;
using WpfPen = System.Windows.Media.Pen;
using WpfPoint = System.Windows.Point;
using WpfSize = System.Windows.Size;

namespace ClaudeUsageTray;

public enum UsageProgressVisualMode
{
    Terminal,
    Orbit,
    Pencil
}

public sealed class UsageProgressBar : System.Windows.Controls.ProgressBar
{
    public static readonly DependencyProperty VisualModeProperty = DependencyProperty.Register(
        nameof(VisualMode), typeof(UsageProgressVisualMode), typeof(UsageProgressBar),
        new FrameworkPropertyMetadata(UsageProgressVisualMode.Terminal));

    public UsageProgressVisualMode VisualMode
    {
        get => (UsageProgressVisualMode)GetValue(VisualModeProperty);
        set => SetValue(VisualModeProperty, value);
    }
}

public sealed class UsageProgressRenderer : FrameworkElement
{
    public static readonly DependencyProperty ValueProperty = RenderProperty(nameof(Value), typeof(double), 0d);
    public static readonly DependencyProperty MinimumProperty = RenderProperty(nameof(Minimum), typeof(double), 0d);
    public static readonly DependencyProperty MaximumProperty = RenderProperty(nameof(Maximum), typeof(double), 100d);
    public static readonly DependencyProperty VisualModeProperty = RenderProperty(
        nameof(VisualMode), typeof(UsageProgressVisualMode), UsageProgressVisualMode.Terminal);
    public static readonly DependencyProperty FillProperty = RenderProperty(
        nameof(Fill), typeof(WpfBrush), System.Windows.Media.Brushes.White);
    public static readonly DependencyProperty TrackProperty = RenderProperty(
        nameof(Track), typeof(WpfBrush), System.Windows.Media.Brushes.Gray);

    public double Value { get => (double)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
    public double Minimum { get => (double)GetValue(MinimumProperty); set => SetValue(MinimumProperty, value); }
    public double Maximum { get => (double)GetValue(MaximumProperty); set => SetValue(MaximumProperty, value); }
    public UsageProgressVisualMode VisualMode
    {
        get => (UsageProgressVisualMode)GetValue(VisualModeProperty);
        set => SetValue(VisualModeProperty, value);
    }
    public WpfBrush Fill { get => (WpfBrush)GetValue(FillProperty); set => SetValue(FillProperty, value); }
    public WpfBrush Track { get => (WpfBrush)GetValue(TrackProperty); set => SetValue(TrackProperty, value); }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var ratio = Maximum <= Minimum ? 0 : Math.Clamp((Value - Minimum) / (Maximum - Minimum), 0, 1);
        if (VisualMode == UsageProgressVisualMode.Orbit) DrawCircular(drawingContext, ratio);
        else if (VisualMode == UsageProgressVisualMode.Pencil) DrawPencil(drawingContext, ratio);
        else DrawTerminal(drawingContext, ratio);
    }

    private void DrawTerminal(DrawingContext drawingContext, double ratio)
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var cellCount = Math.Clamp((int)Math.Floor((ActualWidth - 18) / 7), 6, 22);
        var filledCount = (int)Math.Round(ratio * cellCount, MidpointRounding.AwayFromZero);
        var typeface = new Typeface(new System.Windows.Media.FontFamily("Cascadia Mono, Consolas"), FontStyles.Normal,
            FontWeights.SemiBold, FontStretches.Normal);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var fontSize = 11d;

        var open = TerminalText("[", typeface, fontSize, Fill, dpi);
        var filled = TerminalText(new string('█', filledCount), typeface, fontSize, Fill, dpi);
        var empty = TerminalText(new string('░', cellCount - filledCount), typeface, fontSize, Track, dpi);
        var close = TerminalText("]", typeface, fontSize, Fill, dpi);
        var totalWidth = open.WidthIncludingTrailingWhitespace + filled.WidthIncludingTrailingWhitespace +
                         empty.WidthIncludingTrailingWhitespace + close.WidthIncludingTrailingWhitespace;
        var scale = totalWidth > ActualWidth ? ActualWidth / totalWidth : 1d;
        var y = Math.Max(0, (ActualHeight - open.Height * scale) / 2);

        drawingContext.PushTransform(new ScaleTransform(scale, scale));
        var x = 0d;
        var scaledY = y / scale;
        drawingContext.DrawText(open, new WpfPoint(x, scaledY));
        x += open.WidthIncludingTrailingWhitespace;
        drawingContext.DrawText(filled, new WpfPoint(x, scaledY));
        x += filled.WidthIncludingTrailingWhitespace;
        drawingContext.DrawText(empty, new WpfPoint(x, scaledY));
        x += empty.WidthIncludingTrailingWhitespace;
        drawingContext.DrawText(close, new WpfPoint(x, scaledY));
        drawingContext.Pop();
    }

    private void DrawCircular(DrawingContext drawingContext, double ratio)
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var center = new WpfPoint(ActualWidth / 2, ActualHeight / 2);
        var radius = Math.Max(7, Math.Min(ActualWidth, ActualHeight) / 2 - 3);
        var trackPen = new WpfPen(Track, 3);
        var progressPen = new WpfPen(Fill, 3.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        drawingContext.DrawEllipse(null, trackPen, center, radius, radius);
        if (ratio <= 0) return;
        drawingContext.DrawGeometry(null, progressPen, CreateCircularArc(center, radius, ratio));
        var angle = -90 + ratio * 359.999;
        var radians = angle * Math.PI / 180d;
        var planet = new WpfPoint(center.X + radius * Math.Cos(radians), center.Y + radius * Math.Sin(radians));
        drawingContext.DrawEllipse(Fill, new WpfPen(Track, 1), planet, 3.7, 3.7);
    }

    private static Geometry CreateCircularArc(WpfPoint center, double radius, double ratio)
    {
        var angle = Math.Clamp(ratio, 0, 1) * 359.999;
        var start = new WpfPoint(center.X, center.Y - radius);
        var radians = (angle - 90) * Math.PI / 180d;
        var end = new WpfPoint(center.X + radius * Math.Cos(radians), center.Y + radius * Math.Sin(radians));
        var figure = new PathFigure { StartPoint = start, IsClosed = false };
        figure.Segments.Add(new ArcSegment(end, new WpfSize(radius, radius), 0, angle > 180,
            SweepDirection.Clockwise, true));
        return new PathGeometry([figure]);
    }

    private void DrawPencil(DrawingContext drawingContext, double ratio)
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var centerY = ActualHeight / 2;
        drawingContext.DrawGeometry(null, new WpfPen(Track, 1.2),
            CreateRoughLine(ActualWidth, centerY, 0.7, 0.68));

        var filledWidth = ActualWidth * ratio;
        if (filledWidth <= 0) return;
        for (var pass = -1; pass <= 1; pass++)
        {
            var pen = new WpfPen(Fill, pass == 0 ? 1.8 : 1.15)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round
            };
            drawingContext.DrawGeometry(null, pen,
                CreateRoughLine(filledWidth, centerY + pass * 1.25, 1.3 + pass * 0.37, 1.06));
        }

        var grain = Fill.CloneCurrentValue();
        grain.Opacity = 0.42;
        var grainPen = new WpfPen(grain, 0.8);
        for (var x = 3d; x < filledWidth - 1; x += 5.5)
            drawingContext.DrawLine(grainPen,
                new WpfPoint(x, centerY + 3.2), new WpfPoint(Math.Min(x + 3.5, filledWidth), centerY - 3.2));
    }

    private static Geometry CreateRoughLine(double width, double centerY, double phase, double roughness)
    {
        double Offset(double x) =>
            (Math.Sin(x * 0.47 + phase) * 0.82 + Math.Sin(x * 0.16 + phase * 1.9) * 0.28) * roughness;
        var figure = new PathFigure { StartPoint = new WpfPoint(0, centerY + Offset(0)) };
        var points = new PointCollection();
        for (var index = 1; ; index++)
        {
            var x = index * 4d + Math.Sin(index * 1.7 + phase) * 0.55;
            if (x >= width) break;
            points.Add(new WpfPoint(x, centerY + Offset(x)));
        }
        points.Add(new WpfPoint(width, centerY + Offset(width)));
        figure.Segments.Add(new PolyLineSegment(points, true));
        return new PathGeometry([figure]);
    }

    private static FormattedText TerminalText(string text, Typeface typeface, double size, WpfBrush brush, double dpi) =>
        new(text, CultureInfo.InvariantCulture, System.Windows.FlowDirection.LeftToRight, typeface, size, brush, dpi);

    private static DependencyProperty RenderProperty(string name, Type type, object defaultValue) =>
        DependencyProperty.Register(name, type, typeof(UsageProgressRenderer),
            new FrameworkPropertyMetadata(defaultValue, FrameworkPropertyMetadataOptions.AffectsRender));
}
