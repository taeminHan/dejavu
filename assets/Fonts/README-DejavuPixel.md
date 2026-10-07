# Dejavu Pixel

Original 5 x 7 bitmap alphabet and generated TrueType font, licensed under the repository's MIT license. No third-party font, font installer or runtime font library is used.

`RetroPixelVisuals.cs` owns 44 bitmap patterns; lowercase Latin characters reuse their uppercase patterns. `tools/BuildPixelFont.cjs` compiles 71 glyphs including `.notdef`, checks the font checksum and emits `DejavuPixel-Regular.ttf`. The project embeds the font as a WPF resource. Generate it from the repository root with Node:

```powershell
node .\tools\BuildPixelFont.cjs .
```

Digits, percent signs and short Latin labels use the bitmap face in Retro Night. Korean and unsupported characters use the native readable fallback; they are not claimed to be a bundled Hangul pixel font. `RetroPixelText` retains native TextBlock measurement and UI Automation, and disables glyph smoothing only for supported bitmap strings. Resource font families constructed in code require the explicit assembly base URI in ThemeManager; do not silently fall back to a system monospace font.

The glyphs are square outlines, not a low-resolution screenshot stretched over the UI. Check native physical display scaling separately; fractional DPI can distribute a logical pixel over unequal device pixels.
