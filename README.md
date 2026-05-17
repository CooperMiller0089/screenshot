# Screenshot · 截图

A lightweight macOS menu bar app for full-screen, region, and scrolling screenshots — with configurable global hotkeys and automatic clipboard copy.

## Features

- **Full-screen capture** — captures all connected displays instantly
- **Region capture** — drag to select any area with a live overlay
- **Scroll capture** — auto-scrolls the target window and stitches frames into one tall image using overlap-aware template matching; press ESC to stop early
- **Global hotkeys** — fully configurable shortcuts, registered system-wide via Carbon API (no Input Monitoring permission required)
- **Clipboard copy** — every capture is automatically copied to the clipboard alongside the saved file
- **Minimal UI** — menu bar app with a clean panel; no Dock icon

## Requirements

- macOS 15.7 or later
- Xcode 16 or later (to build from source)

## Permissions

The app will request the following permissions on first use:

| Permission | Required for |
|---|---|
| Screen Recording | All capture modes |
| Accessibility | Scroll capture (auto-scroll simulation) |

## Building

1. Clone the repo:
   ```bash
   git clone git@github.com:CooperMiller0089/screenshot.git
   cd screenshot
   ```
2. Open `Screenshot.xcodeproj` in Xcode
3. Select your development team under **Signing & Capabilities**
4. Press **⌘R** to build and run

The app appears in the menu bar. Click the icon to open the panel.

## Usage

| Action | Default shortcut |
|---|---|
| Full-screen capture | Configurable in app |
| Region capture | Configurable in app |
| Scroll capture | Configurable in app |

Screenshots are saved to `~/Pictures/Screenshots/` and copied to the clipboard automatically.

To change shortcuts, open the app panel and click any key badge in the **快捷键** section.

## How Scroll Capture Works

1. Select the capture region with the overlay
2. The app simulates scroll wheel events, captures a frame every ~35% of the region height, and detects when the page bottom is reached (3 consecutive unchanged frames)
3. Frames are stitched using SAD-based template matching at 15% scale to find the exact pixel overlap between consecutive frames — no gaps, no duplicate content
4. Press **ESC** at any time to stop and stitch what has been captured so far

## Version History

| Version | Changes |
|---|---|
| v1.1.1 | Fix: clipboard now writes PNG + TIFF (fixes paste in Figma, Notion, etc.); full-screen and region captures show "截图完成" toast on completion |
| v1.1.0 | UI redesign — Claude design language (warm palette, Georgia serif, terracotta accent) |
| v1.0.2 | Fix: toast notification no longer appears in scroll capture frames |
| v1.0.1 | Fix: missing bottom content in scroll captures (both auto-stop and ESC exit) |
| v1.0.0 | Initial release |

## License

MIT
