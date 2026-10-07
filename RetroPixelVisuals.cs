using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Point = System.Windows.Point;

namespace ClaudeUsageTray;

/// <summary>Original 5 x 7 bitmap alphabet, compiled by tools/BuildPixelFont.cjs into a bundled font.
/// Native TextBlock measurement, automation and Korean font fallback stay intact.</summary>
public sealed class RetroPixelText : TextBlock
{
    public static readonly DependencyProperty PixelEnabledProperty = DependencyProperty.Register(
        nameof(PixelEnabled), typeof(bool), typeof(RetroPixelText),
        new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsMeasure |
            FrameworkPropertyMetadataOptions.AffectsRender, OnPixelTextChanged));
    public bool PixelEnabled { get => (bool)GetValue(PixelEnabledProperty); set => SetValue(PixelEnabledProperty, value); }

    private static readonly Dictionary<char, string> Glyphs = new()
    {
        ['0']="01110/10001/10011/10101/11001/10001/01110", ['1']="00100/01100/00100/00100/00100/00100/01110",
        ['2']="01110/10001/00001/00010/00100/01000/11111", ['3']="11110/00001/00001/01110/00001/00001/11110",
        ['4']="00010/00110/01010/10010/11111/00010/00010", ['5']="11111/10000/10000/11110/00001/00001/11110",
        ['6']="01110/10000/10000/11110/10001/10001/01110", ['7']="11111/00001/00010/00100/01000/01000/01000",
        ['8']="01110/10001/10001/01110/10001/10001/01110", ['9']="01110/10001/10001/01111/00001/00001/01110",
        ['A']="01110/10001/10001/11111/10001/10001/10001", ['B']="11110/10001/10001/11110/10001/10001/11110",
        ['C']="01111/10000/10000/10000/10000/10000/01111", ['D']="11110/10001/10001/10001/10001/10001/11110",
        ['E']="11111/10000/10000/11110/10000/10000/11111", ['F']="11111/10000/10000/11110/10000/10000/10000",
        ['G']="01111/10000/10000/10111/10001/10001/01111", ['H']="10001/10001/10001/11111/10001/10001/10001",
        ['I']="01110/00100/00100/00100/00100/00100/01110", ['J']="00111/00010/00010/00010/00010/10010/01100",
        ['K']="10001/10010/10100/11000/10100/10010/10001", ['L']="10000/10000/10000/10000/10000/10000/11111",
        ['M']="10001/11011/10101/10101/10001/10001/10001", ['N']="10001/11001/10101/10011/10001/10001/10001",
        ['O']="01110/10001/10001/10001/10001/10001/01110", ['P']="11110/10001/10001/11110/10000/10000/10000",
        ['Q']="01110/10001/10001/10001/10101/10010/01101", ['R']="11110/10001/10001/11110/10100/10010/10001",
        ['S']="01111/10000/10000/01110/00001/00001/11110", ['T']="11111/00100/00100/00100/00100/00100/00100",
        ['U']="10001/10001/10001/10001/10001/10001/01110", ['V']="10001/10001/10001/10001/10001/01010/00100",
        ['W']="10001/10001/10001/10101/10101/11011/10001", ['X']="10001/10001/01010/00100/01010/10001/10001",
        ['Y']="10001/10001/01010/00100/00100/00100/00100", ['Z']="11111/00001/00010/00100/01000/10000/11111",
        ['%']="11001/11010/00100/01000/10110/00110/00000", ['-']="00000/00000/00000/11111/00000/00000/00000",
        ['/']="00001/00010/00010/00100/01000/01000/10000", [':']="00000/00100/00100/00000/00100/00100/00000",
        ['.']="00000/00000/00000/00000/00000/00100/00100", ['[']="01110/01000/01000/01000/01000/01000/01110",
        [']']="01110/00010/00010/00010/00010/00010/01110", [' ']= "00000/00000/00000/00000/00000/00000/00000"
    };
    public bool UsesPixels => PixelEnabled && Text.Length > 0 && Text.ToUpperInvariant().All(Glyphs.ContainsKey);
    static RetroPixelText() => TextProperty.OverrideMetadata(typeof(RetroPixelText),
        new FrameworkPropertyMetadata(string.Empty, OnPixelTextChanged));

    private static void OnPixelTextChanged(DependencyObject sender, DependencyPropertyChangedEventArgs e)
    {
        var text = (RetroPixelText)sender;
        TextOptions.SetTextRenderingMode(text, text.UsesPixels ? TextRenderingMode.Aliased : TextRenderingMode.Grayscale);
    }
}

/// <summary>Non-interactive pixel-step frame; does not add a layout slot or a window owner.</summary>
public sealed class RetroPixelFrame : FrameworkElement
{
    public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(nameof(Stroke),
        typeof(Brush), typeof(RetroPixelFrame), new FrameworkPropertyMetadata(System.Windows.Media.Brushes.Gray,
            FrameworkPropertyMetadataOptions.AffectsRender));
    public Brush Stroke { get => (Brush)GetValue(StrokeProperty); set => SetValue(StrokeProperty, value); }
    public RetroPixelFrame() { IsHitTestVisible = false; RenderOptions.SetEdgeMode(this, EdgeMode.Aliased); }
    protected override void OnRender(DrawingContext dc)
    {
        var w = Math.Floor(ActualWidth); var h = Math.Floor(ActualHeight);
        if (w < 16 || h < 16) return;
        dc.DrawRectangle(Stroke, null, new Rect(6, 0, w - 12, 2));
        dc.DrawRectangle(Stroke, null, new Rect(6, h - 2, w - 12, 2));
        dc.DrawRectangle(Stroke, null, new Rect(0, 6, 2, h - 12));
        dc.DrawRectangle(Stroke, null, new Rect(w - 2, 6, 2, h - 12));
        foreach (var right in new[] { false, true })
        foreach (var bottom in new[] { false, true })
        {
            double X(double x) => right ? w - x - 2 : x;
            double Y(double y) => bottom ? h - y - 2 : y;
            foreach (var p in new[] { new Point(4, 2), new Point(2, 4) })
                dc.DrawRectangle(Stroke, null, new Rect(X(p.X), Y(p.Y), 2, 2));
        }
    }
}
