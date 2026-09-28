# Provider brand assets

The menu bar uses provider artwork only to identify the service whose usage is
shown. Dejavu's own `clock.arrow.circlepath` symbol remains the primary status
item image.

- `ClaudeSparkMenuBar.imageset` is the standalone Claude Spark from Anthropic's
  official press kit, downloaded from <https://www.anthropic.com/press-kit>.
  AppKit uses its alpha mask as a monochrome menu bar template.
- `CodexMenuBar.imageset` is the monochrome OpenAI Blossom template distributed
  in the official macOS ChatGPT application. AppKit tints it for the current
  menu bar appearance and highlighted state.

Both assets retain their original shape and aspect ratio. AppKit gives both
templates their semantic menu bar color. The files are only proportionally
downscaled for the macOS menu bar.
Claude and Anthropic marks belong to Anthropic. Codex and OpenAI marks belong
to OpenAI.

# App icon

`AppIcon.appiconset` is Dejavu's own mark, not provider artwork. Its source is
`assets/brand-mark.svg`, the same rounded square with the `#7898FF` to
`#526FE8` gradient, white ring and white vertical line that
`tools/GenerateIcon.ps1` renders for the Windows icon.

The PNGs are generated, not hand-edited. Regenerate them from the repository
root after changing the mark:

```bash
swift tools/GenerateMacAppIcon.swift macos/DejavuMac/Resources/BrandAssets.xcassets/AppIcon.appiconset
```

The script needs only the Command Line Tools and uses CoreGraphics and ImageIO.
It follows the macOS app icon grid: a transparent 1024 × 1024 canvas, an
824 × 824 continuous-corner body with a 100 px margin and a corner radius of
about 185 px, and a subtle drop shadow inside the margin. Each of the 16, 32,
64, 128, 256, 512 and 1024 px images is drawn natively from the vector geometry
as 8-bit sRGB RGBA. The DejavuMac target selects the set through
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, and the asset catalog compiler
adds the icon keys to the built `Info.plist`.
