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

public enum OrbitBodyKind
{
    Sun,
    Earth,
    Moon,
    Saturn
}

public sealed class UsageProgressBar : System.Windows.Controls.ProgressBar
{
    public static readonly DependencyProperty VisualModeProperty = DependencyProperty.Register(
        nameof(VisualMode), typeof(UsageProgressVisualMode), typeof(UsageProgressBar),
        new FrameworkPropertyMetadata(UsageProgressVisualMode.Terminal));
    public static readonly DependencyProperty OrbitBodyProperty = DependencyProperty.Register(
        nameof(OrbitBody), typeof(OrbitBodyKind), typeof(UsageProgressBar),
        new FrameworkPropertyMetadata(OrbitBodyKind.Earth));

    public UsageProgressVisualMode VisualMode
    {
        get => (UsageProgressVisualMode)GetValue(VisualModeProperty);
        set => SetValue(VisualModeProperty, value);
    }

    public OrbitBodyKind OrbitBody
    {
        get => (OrbitBodyKind)GetValue(OrbitBodyProperty);
        set => SetValue(OrbitBodyProperty, value);
    }
}

public sealed class UsageProgressRenderer : FrameworkElement
{
    public static readonly DependencyProperty ValueProperty = RenderProperty(nameof(Value), typeof(double), 0d);
    public static readonly DependencyProperty MinimumProperty = RenderProperty(nameof(Minimum), typeof(double), 0d);
    public static readonly DependencyProperty MaximumProperty = RenderProperty(nameof(Maximum), typeof(double), 100d);
    public static readonly DependencyProperty VisualModeProperty = RenderProperty(
        nameof(VisualMode), typeof(UsageProgressVisualMode), UsageProgressVisualMode.Terminal);
    public static readonly DependencyProperty OrbitBodyProperty = RenderProperty(
        nameof(OrbitBody), typeof(OrbitBodyKind), OrbitBodyKind.Earth);
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
    public OrbitBodyKind OrbitBody
    {
        get => (OrbitBodyKind)GetValue(OrbitBodyProperty);
        set => SetValue(OrbitBodyProperty, value);
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
        OrbitBodyPainter.Draw(drawingContext, planet, 4.8, OrbitBody, Fill, Track,
            key => TryFindResource(key) as WpfBrush);
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

public sealed class OrbitBodyMarker : FrameworkElement
{
    public static readonly DependencyProperty BodyProperty = RenderProperty(
        nameof(Body), typeof(OrbitBodyKind), OrbitBodyKind.Earth);
    public static readonly DependencyProperty FillProperty = RenderProperty(
        nameof(Fill), typeof(WpfBrush), System.Windows.Media.Brushes.White);
    public static readonly DependencyProperty TrackProperty = RenderProperty(
        nameof(Track), typeof(WpfBrush), System.Windows.Media.Brushes.Gray);

    public OrbitBodyKind Body { get => (OrbitBodyKind)GetValue(BodyProperty); set => SetValue(BodyProperty, value); }
    public WpfBrush Fill { get => (WpfBrush)GetValue(FillProperty); set => SetValue(FillProperty, value); }
    public WpfBrush Track { get => (WpfBrush)GetValue(TrackProperty); set => SetValue(TrackProperty, value); }

    public OrbitBodyMarker()
    {
        IsHitTestVisible = false;
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var center = new WpfPoint(ActualWidth / 2, ActualHeight / 2);
        var radius = Math.Max(2, Math.Min(ActualWidth, ActualHeight) / 2 - 1);
        OrbitBodyPainter.Draw(drawingContext, center, radius, Body, Fill, Track,
            key => TryFindResource(key) as WpfBrush);
    }

    private static DependencyProperty RenderProperty(string name, Type type, object defaultValue) =>
        DependencyProperty.Register(name, type, typeof(OrbitBodyMarker),
            new FrameworkPropertyMetadata(defaultValue, FrameworkPropertyMetadataOptions.AffectsRender));
}

internal static class OrbitBodyPainter
{
    internal static void Draw(DrawingContext drawingContext, WpfPoint center, double radius, OrbitBodyKind body,
        WpfBrush fallbackFill, WpfBrush fallbackTrack, Func<string, WpfBrush?> resolveBrush)
    {
        if (radius <= 0) return;
        var outline = resolveBrush("OrbitBodyOutlineBrush") ?? fallbackTrack;
        var outlinePen = new WpfPen(outline, Math.Max(0.75, radius * 0.22));

        switch (body)
        {
            case OrbitBodyKind.Sun:
                DrawSun(drawingContext, center, radius,
                    resolveBrush("OrbitSunBrush") ?? fallbackFill,
                    resolveBrush("OrbitSunCoreBrush") ?? fallbackFill,
                    outlinePen);
                break;
            case OrbitBodyKind.Moon:
                DrawMoon(drawingContext, center, radius,
                    resolveBrush("OrbitMoonBrush") ?? fallbackFill,
                    resolveBrush("OrbitMoonDetailBrush") ?? fallbackTrack,
                    outlinePen);
                break;
            case OrbitBodyKind.Saturn:
                DrawSaturn(drawingContext, center, radius,
                    resolveBrush("OrbitSaturnBrush") ?? fallbackFill,
                    resolveBrush("OrbitSaturnBandBrush") ?? fallbackTrack,
                    resolveBrush("OrbitSaturnRingBrush") ?? fallbackFill,
                    outlinePen);
                break;
            default:
                DrawEarth(drawingContext, center, radius,
                    resolveBrush("OrbitEarthBrush") ?? fallbackFill,
                    resolveBrush("OrbitEarthLandBrush") ?? fallbackTrack,
                    outlinePen);
                break;
        }
    }

    private static void DrawSun(DrawingContext drawingContext, WpfPoint center, double radius,
        WpfBrush surface, WpfBrush core, WpfPen outlinePen)
    {
        var rayPen = new WpfPen(surface, Math.Max(0.8, radius * 0.24))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        for (var index = 0; index < 8; index++)
        {
            var radians = index * Math.PI / 4d;
            var inner = radius * 1.08;
            var outer = radius * 1.42;
            drawingContext.DrawLine(rayPen,
                new WpfPoint(center.X + Math.Cos(radians) * inner, center.Y + Math.Sin(radians) * inner),
                new WpfPoint(center.X + Math.Cos(radians) * outer, center.Y + Math.Sin(radians) * outer));
        }

        var surfaceRadius = radius * 0.82;
        drawingContext.DrawEllipse(surface, outlinePen, center, surfaceRadius, surfaceRadius);
        drawingContext.DrawEllipse(core, null,
            new WpfPoint(center.X - radius * 0.2, center.Y - radius * 0.2), radius * 0.26, radius * 0.26);
    }

    private static void DrawEarth(DrawingContext drawingContext, WpfPoint center, double radius,
        WpfBrush ocean, WpfBrush land, WpfPen outlinePen)
    {
        drawingContext.DrawEllipse(ocean, outlinePen, center, radius, radius);
        drawingContext.PushClip(new EllipseGeometry(center, radius * 0.9, radius * 0.9));
        drawingContext.DrawEllipse(land, null,
            new WpfPoint(center.X - radius * 0.3, center.Y - radius * 0.22), radius * 0.34, radius * 0.2);
        drawingContext.DrawEllipse(land, null,
            new WpfPoint(center.X + radius * 0.34, center.Y + radius * 0.22), radius * 0.27, radius * 0.24);
        drawingContext.Pop();
    }

    private static void DrawMoon(DrawingContext drawingContext, WpfPoint center, double radius,
        WpfBrush surface, WpfBrush detail, WpfPen outlinePen)
    {
        drawingContext.DrawEllipse(surface, outlinePen, center, radius, radius);
        drawingContext.DrawEllipse(detail, null,
            new WpfPoint(center.X - radius * 0.28, center.Y - radius * 0.18), radius * 0.2, radius * 0.2);
        drawingContext.DrawEllipse(detail, null,
            new WpfPoint(center.X + radius * 0.3, center.Y + radius * 0.24), radius * 0.16, radius * 0.16);
        drawingContext.DrawEllipse(detail, null,
            new WpfPoint(center.X + radius * 0.24, center.Y - radius * 0.34), radius * 0.1, radius * 0.1);
    }

    private static void DrawSaturn(DrawingContext drawingContext, WpfPoint center, double radius,
        WpfBrush surface, WpfBrush band, WpfBrush ring, WpfPen outlinePen)
    {
        var bodyRadius = radius * 0.76;
        var ringRadiusX = radius * 1.55;
        var ringRadiusY = radius * 0.52;
        var ringOutlinePen = new WpfPen(outlinePen.Brush, Math.Max(1, radius * 0.34))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        var ringPen = new WpfPen(ring, Math.Max(0.8, radius * 0.2))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };

        drawingContext.PushTransform(new RotateTransform(-16, center.X, center.Y));

        // Paint the whole ring behind the planet first, then restore only the
        // front half after the body so the overlap still reads at marker size.
        drawingContext.DrawEllipse(null, ringOutlinePen, center, ringRadiusX, ringRadiusY);
        drawingContext.DrawEllipse(null, ringPen, center, ringRadiusX, ringRadiusY);
        drawingContext.DrawEllipse(surface, outlinePen, center, bodyRadius, bodyRadius);

        drawingContext.PushClip(new EllipseGeometry(center, bodyRadius * 0.92, bodyRadius * 0.92));
        var bandPen = new WpfPen(band, Math.Max(0.65, radius * 0.17))
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        drawingContext.DrawLine(bandPen,
            new WpfPoint(center.X - bodyRadius * 0.68, center.Y),
            new WpfPoint(center.X + bodyRadius * 0.68, center.Y));
        drawingContext.Pop();

        var frontRing = new PathFigure
        {
            StartPoint = new WpfPoint(center.X - ringRadiusX, center.Y),
            IsClosed = false
        };
        frontRing.Segments.Add(new ArcSegment(
            new WpfPoint(center.X + ringRadiusX, center.Y),
            new WpfSize(ringRadiusX, ringRadiusY), 0, false,
            SweepDirection.Counterclockwise, true));
        var frontGeometry = new PathGeometry([frontRing]);
        drawingContext.DrawGeometry(null, ringOutlinePen, frontGeometry);
        drawingContext.DrawGeometry(null, ringPen, frontGeometry);

        drawingContext.Pop();
    }
}
