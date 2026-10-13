# Dejavu macOS application icon

`Dejavu.icns` is the packaged application identity, generated from the original
repository-owned **Familiar Paradox / 모순의 프레임** vector at
`design/prototype/brand-mark.svg`. This is not a Claude or OpenAI provider icon.
The original SVG and provider assets/licensing are preserved unchanged.

Regenerate from the repository root on macOS:

```bash
swift -module-cache-path /tmp/dejavu-icon-cache tools/GenerateMacAppIcon.swift
```

The generator uses AppKit's SVG renderer and Apple's `iconutil` to include the
standard 16, 32, 128, 256 and 512 point representations at 1×/2×. The app target
copies `Dejavu.icns` and declares `CFBundleIconFile`; the menu-bar identity remains
separate and the app continues to be an `LSUIElement` utility without a Dock entry.
