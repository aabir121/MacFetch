# Download Analytics Dashboard Design

## Intent

MacFetch already helps the user control active downloads, but the current main window is optimized for individual file management. This feature adds a full-screen Overview dashboard that answers: how much was downloaded, how fast, when activity happened, and whether transfers are healthy. It should make the app useful as both a live monitor and a lightweight historical report.

## Goals

- Add a dedicated full-screen Overview surface reachable from the main app.
- Show configurable time ranges: Today, 7 days, 30 days, and a custom date range.
- Show downloads completed, total data downloaded, average speed, peak speed, low speed, success rate, and average transfer duration where data exists.
- Provide one primary chart that can switch between Downloads, Data, and Speed, with daily/weekly/monthly aggregation appropriate to the selected range.
- Preserve the existing download list and detail view as the operational workspace.
- Persist enough transfer history to make analytics survive app restarts.
- Keep the history model extensible for a later analytics-first workspace.

## Non-goals

- No cloud sync, account system, or cross-device aggregation.
- No bandwidth throttling, scheduling, queue priority, or notification work in this feature.
- No server-side network telemetry beyond what the app already observes during downloads.
- No destructive cleanup of existing download records.

## Anti-goals

- Do not make the primary download workflow depend on the dashboard.
- Do not present in-memory speed samples as long-term history.
- Do not imply precision that the app cannot support; periods without samples should be treated as missing data rather than zero-speed activity.

## Product behavior

The main window gains an Overview selection above the existing download filters. Overview opens a full-window dashboard with a compact header, a range control, and a primary chart. The user can switch the chart metric between Downloads, Data, and Speed. The aggregation label changes between day, week, and month based on the chosen range, with the custom range using the smallest useful bucket count for readability.

The first row contains KPI cards for total downloads, data downloaded, average speed, and peak speed. A second row contains a large chart and a supporting insight panel with low speed, success rate, average duration, and most active period. A recent activity table below shows the latest completed and failed transfers, with file name, type, size, duration, average speed, and status. Existing add-download controls remain available from the dashboard header.

The range picker defaults to the last 7 days. Today and 7 days show hourly/daily detail as space allows; 30 days shows daily detail; longer custom ranges aggregate by week or month. A custom picker stores the currently selected range only for the current session initially.

## Data model

Add a persisted `DownloadSample` SwiftData model with a timestamp, record identifier, cumulative downloaded bytes, instantaneous speed, and optional state marker. The manager records a coarse sample once per second while transfers are active and writes a bounded batch to SwiftData. Samples are retained for analytics; the implementation may prune only samples older than a conservative retention window if storage becomes a concern, but the first version should not prune.

Add persisted timing fields to `DownloadRecord` as optional values: startedAt, completedAt, and peakSpeed. Existing records remain valid with nil timing values. The manager sets startedAt when a job begins, updates peakSpeed from its existing tick calculation, and sets completedAt on terminal success or failure. Historical calculations use the fields that exist and omit unavailable durations.

Dashboard aggregation is derived in memory from the selected records and samples. The aggregation layer should be a small value-type service or helper that accepts records, samples, a date range, metric, and bucket policy, returning chart points plus summary metrics. This keeps a later analytics-first screen from duplicating date math.

## Approaches

### A. Persist raw samples and derive summaries in the UI (recommended)

Store coarse raw samples and calculate summaries when the dashboard changes range or metric. This is simplest, keeps the source of truth inspectable, and gives the later analytics workspace flexibility. The tradeoff is modest in-memory aggregation work, which is acceptable for a local download manager.

### B. Persist pre-aggregated daily/weekly summaries

Write summary rows as downloads progress. This makes charts cheap but complicates corrections, date-range changes, and historical migrations. It also makes later granularity changes harder.

### C. Keep only the existing records and infer history

This requires no new model but cannot provide real speed history, accurate durations, or meaningful low/peak values after a restart. It does not satisfy the request.

## Chosen approach

Use A. The current app already has per-second live metrics in `DownloadManager`, and raw samples provide the right foundation for both the requested monitor-first view and the later analytics-first workspace. Build the monitor-first dashboard and shared aggregation layer now; defer the denser linked-chart/reporting surface until the first dashboard has been validated.

## Visual direction

Use the existing macOS SwiftUI language: system materials, restrained accent color, native Charts, and strong hierarchy rather than a decorative custom theme. The dashboard should feel like a calm control room: quiet neutral background, one accent for healthy activity, warm warning treatment for failures, and generous chart area in full-screen mode. The layout must collapse cleanly to narrower windows.

## Open implementation calls

- The builder should choose the exact chart bucket algorithm and sample retention details, provided the behavior above remains true.
- The builder should add small previews or fixture data only if needed to validate the layout; production analytics must use real persisted data.
- CSV export is deferred to the second analytics phase unless the implementation is nearly free after the first dashboard is complete.

## Product decisions

- “Downloads completed” counts unique records that reach Completed. Failed and cancelled records are excluded from the success numerator but included in the denominator once they have started. Retries update the same record rather than creating another analytics event.
- Average speed is byte-weighted across observed transfer time. Peak and low speed use active samples only, excluding idle zeroes and startup gaps.
- Existing records remain visible in history. Records without timing or sample data contribute to counts and bytes when their dates and sizes exist, but not to speed or duration metrics.
- Presets and custom ranges use the Mac’s local calendar and time zone. A custom end date includes the full selected day.
- Active or incomplete transfers appear as “In progress” with partial metrics; unavailable values are shown as “—”, never as zero.
- “Full-screen” means an in-app Overview mode that fills the main window and keeps the existing download workspace one click away. Native macOS full-screen remains available through the window controls.

## Success criteria

- Opening Overview shows a complete dashboard without requiring a download to be active.
- Changing the range or metric updates KPI values and the chart from persisted data.
- Quitting and reopening the app preserves history for completed downloads and their samples.
- Active downloads continue to work from the existing list and menu bar.
- The project builds successfully with the macOS 14 SDK.
