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
