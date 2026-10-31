# MacFetch

MacFetch is a native macOS download manager with a SwiftUI interface, menu-bar controls, and a Chrome extension that forwards browser downloads into the app.

## Features

- Parallel HTTP downloads with range probing and single-stream fallback.
- Live progress, aggregate speed, pause, resume, stop, retry, and failure details.
- Multi-select downloads with bulk pause, resume, stop, and remove actions.
- Menu-bar list showing active downloads with progress and quick controls.
- Chrome download interception through Native Messaging.
- Configurable confirmation prompt for Chrome-captured downloads.
- Persistent download location selection with exact browser-provided filenames.
- Type filtering, time/name sorting, and grouping by type or day.
- SwiftData persistence and recovery of interrupted downloads.
- Finder reveal/open actions and drag-and-drop URL support.

## Requirements

- macOS 14 or later.
- Xcode with the macOS SDK installed.
- Google Chrome for the browser extension integration.

## Build the app

```sh
xcodebuild \
  -project MacFetch.xcodeproj \
  -scheme MacFetch \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/macfetch-derived \
  build
```

The built application is produced at `Build/Products/Release/MacFetch.app` inside the derived-data directory. For local use, copy it to `/Applications` or `~/Applications`.

## Install the Chrome integration

1. Build and install `MacFetch.app` at `~/Applications/MacFetch.app`.
2. Open `chrome://extensions` in Chrome.
3. Enable **Developer mode**.
4. Choose **Load unpacked** and select the `Extension` directory.
5. Copy the extension ID shown by Chrome.
6. Replace `__EXTENSION_ID__` in `NativeHost/manifest.template.json` with that ID.
7. Install the native host manifest at:

   `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.macfetch.native.json`

   The manifest must point to:

   `~/Applications/MacFetch.app/Contents/Resources/macfetch-native-host`

After installation, downloads started in Chrome are forwarded to MacFetch through the native messaging bridge. The included `NativeHost/com.macfetch.native.json` contains the extension ID used by the development installation in this workspace.

## Capture confirmation

MacFetch asks for confirmation before starting a URL captured from Chrome by default. Open **MacFetch > Settings** and change **Ask before downloading captured files** to disable the prompt and start captured downloads automatically.

The same Settings panel lets you choose and remember the destination folder for new downloads. MacFetch waits for Chrome's resolved download filename, preserving the browser-provided name and extension even when they differ from the URL path.

## Installable archive

The latest bundled app, extension, and native host are in:

`dist/MacFetch-1.1.3-bulk-operations.zip`

## Testing

The `TestAssets` directory contains a small local HTTP server and a browser-trigger test asset for validating the Chrome-to-MacFetch pipeline.

## Project layout

| Path | Purpose |
| --- | --- |
| `MacFetch/` | Native SwiftUI app and download engine |
| `Extension/` | Chrome Manifest V3 extension |
| `NativeHost/` | Chrome Native Messaging host and manifest template |
| `TestAssets/` | Local download integration-test fixtures |
| `dist/` | Installable archives |

## License

No license has been selected yet.
