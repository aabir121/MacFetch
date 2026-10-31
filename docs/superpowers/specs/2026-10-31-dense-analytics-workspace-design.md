# Dense Analytics Workspace Design

## Intent

The Overview dashboard answers “how are downloads doing?” at a glance. The second phase adds an analytics-first workspace for answering “why did activity change?” and “which downloads or sources drove it?” without leaving MacFetch.

## Goals

- Add a denser Analytics workspace reachable from the existing sidebar.
- Reuse the existing persisted `DownloadRecord` and `DownloadSample` history.
- Provide one shared date range plus linked filters for file type, status, and source domain.
- Show comparison deltas against the previous equivalent period.
- Provide coordinated charts for volume, speed distribution, outcomes, and file-type/source mix.
- Make chart selections filter the activity table below.
- Export the current filtered activity view as CSV.
- Keep Overview and Downloads focused and unchanged.

## Non-goals

- No draggable dashboard builder, saved layouts, cloud sync, accounts, or remote analytics.
- No changes to download execution, queue scheduling, throttling, or browser capture behavior.
- No statistical forecasting or anomaly detection in this phase.

## Product behavior

Analytics becomes a third sidebar destination alongside Overview and Downloads. It opens a dense workspace that fills the main window and keeps the sidebar visible.

The header contains the shared range selector (Today, 7 days, 30 days, Custom), comparison toggle, and Export CSV action. A filter rail contains file type, status, and source-domain multi-select filters, plus Clear filters. Filters update every KPI, chart, and table together.

The first row contains KPI cards for downloads, data, average speed, success rate, and a delta versus the previous equivalent period. The second row contains two charts: downloads/data volume over time and speed distribution (average/median/peak/low). The third row contains outcomes (completed, failed, cancelled, in progress) and a breakdown chart that can switch between file type and source domain.

The activity table shows filtered records with time, file, type, source domain, status, received size, duration, and average speed. Selecting a chart bucket or breakdown segment applies the corresponding filter to the table and visibly adds a filter chip. Selecting a table row opens the existing detail panel for that download. CSV export uses the currently filtered rows and includes a header row with stable column names.

## Product decisions

- Source domain is derived from `DownloadRecord.url` using `URL.host`, normalized lower-case, with `Local file` for records without a usable host.
- File type uses the existing `DownloadRecord.fileType` value.
- Status filters use the existing state labels; “In progress” is a presentation grouping for downloading and queued records.
- Time ranges use the same local-calendar and inclusive-end-day rules as Overview.
- Previous-period comparison uses the same duration immediately preceding the selected range; Today compares to yesterday, 7 days to the previous 7 days, and custom ranges to the immediately preceding range of equal day count.
- Speed distribution uses positive active samples only; missing speed history displays `—` and does not imply zero.
- CSV export is local and immediate; it uses UTF-8 with comma separators and quotes fields containing commas, quotes, or newlines.

## Data and architecture

Add a shared filter value type and an `AnalyticsWorkspaceModel`/service that derives filtered records, comparison summaries, breakdown buckets, speed distribution values, and CSV rows from the existing arrays. Keep it pure and value-based so it can be tested without SwiftData or UI.

Extend `DownloadAnalytics` rather than duplicating date math. Add source-domain derivation and CSV serialization as small helpers. Keep chart selection state in the workspace view and pass selected filter values into the model.

The workspace should use native SwiftUI `Table`, `Charts`, `Menu`, `Picker`, and `ShareLink`/file export APIs available on macOS 14. If the native file exporter is awkward in the existing app shell, use a save-panel-backed export action with the same CSV bytes.

## Approaches

### A. Linked analysis workspace (recommended)

One shared filter model drives all panels, and chart selection updates that model. This gives the user a coherent “slice and inspect” workflow with a manageable implementation surface. The tradeoff is that charts need careful selection state and empty-state behavior.

### B. Report builder

Allow users to add, remove, resize, and save widgets. This offers maximum flexibility but adds layout persistence, configuration UI, and many states unrelated to download management.

### C. Period comparison report

Center the experience on current-vs-previous period deltas. This is simple and clear, but it does not answer which file types or sources caused the change as well as linked filtering does.

## Chosen approach

Use A, with comparison deltas as a compact supporting feature. The existing Overview already establishes the visual language and raw analytics foundation; this phase adds a pure linked-filter model, denser UI, and export without changing the downloader.

## Success criteria

- Analytics is reachable from the sidebar and fills the primary workspace.
- Changing the date range or any filter updates every KPI, chart, and table consistently.
- Selecting a chart bucket or breakdown segment adds a visible filter and updates the table.
- Previous-period deltas use the same metric rules as the current period.
- CSV export contains only the current filtered table rows with stable headers.
- Existing Overview, Downloads, detail, menu-bar, and Chrome workflows remain available.
