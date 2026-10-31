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
- Full-window Overview dashboard with persisted download history, configurable Today/7 days/30 days/custom ranges, Downloads/Data/Speed charts, and average/peak/low speed insights.
- Linked Analytics workspace with shared filters, period comparisons, outcome and source breakdowns, filtered activity tables, and CSV export.
- SwiftData persistence and recovery of interrupted downloads.
- Finder reveal/open actions and drag-and-drop URL support.

## Requirements

- macOS 14 or later.
- Xcode with the macOS SDK installed.
- Google Chrome for the browser extension integration.

## Build the app

Use the full Xcode developer toolchain. On machines where `xcode-select` points
to Command Line Tools, calling `xcodebuild` without `DEVELOPER_DIR` can fail
before the project is compiled.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MacFetch.xcodeproj \
  -scheme MacFetch \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/macfetch-derived \
  build \
  CODE_SIGNING_ALLOWED=NO
```

The built application is produced at:

`/private/tmp/macfetch-derived/Build/Products/Release/MacFetch.app`

## Install and launch a local build

The following installs the app for the current user. It avoids replacing a
system-wide copy in `/Applications` and is also the path used by the native
messaging manifest in this repository.

```sh
mkdir -p "$HOME/Applications"
ditto \
  /private/tmp/macfetch-derived/Build/Products/Release/MacFetch.app \
  "$HOME/Applications/MacFetch.app"
```

When the build was created with `CODE_SIGNING_ALLOWED=NO`, ad-hoc sign the
installed bundle before launching it. This prevents LaunchServices from
rejecting stale or incomplete signature metadata:

```sh
codesign --force --deep --sign - "$HOME/Applications/MacFetch.app"
codesign --verify --deep --strict "$HOME/Applications/MacFetch.app"
open "$HOME/Applications/MacFetch.app"
```

To confirm the running copy is the newly installed one, open **MacFetch** and
check that the Downloads workspace shows the table columns for State, Filename,
Progress, Size, Speed, Elapsed Time, Estimated Time, and Type. The transfer
rate menu is in the toolbar beside the sort controls.

If `open` reports `kLSNoExecutableErr`, verify that
`Contents/MacOS/MacFetch` exists and repeat the `codesign` command above.

To install system-wide instead, use `/Applications/MacFetch.app` as the
destination and run the copy/sign commands with administrator privileges.

## Run a local download smoke test

Start the repository’s localhost-only fixture server in one terminal:

```sh
python3 TestAssets/server.py
```

In MacFetch, click **Add**, enter the following URL, and click **Download**:

`http://127.0.0.1:8765/macfetch-browser-trigger.txt`

The row should appear in the Downloads table. Use the row’s context menu and
choose **Show Details** to open the speed graph in the right-side inspector.
Stop the fixture server with `Ctrl-C` when finished.

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
