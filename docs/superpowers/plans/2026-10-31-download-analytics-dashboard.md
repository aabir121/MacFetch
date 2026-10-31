# Download Analytics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a full-window Overview dashboard with persisted download history, configurable ranges, KPI summaries, and Downloads/Data/Speed charts while preserving the existing download workspace.

**Architecture:** Extend the SwiftData schema with durable transfer timing and coarse speed samples. Keep analytics calculations in a pure value-type service (`DownloadAnalytics`) that transforms records and samples into bucketed chart points and summary metrics. Add a SwiftUI dashboard view and a navigation toggle in the existing `ContentView`, reusing native Charts and the current `DownloadManager`.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, Charts, macOS 14 SDK, existing Xcode project.

**Spec:** `docs/superpowers/specs/2026-10-31-download-analytics-dashboard-design.md`

## Global Constraints

- No cloud sync, account system, or cross-device aggregation.
- Existing download list, detail view, menu-bar controls, and Chrome integration must keep working.
- Presets and custom ranges use the Mac’s local calendar and time zone; custom end dates include the full selected day.
- Existing records remain visible; unavailable metrics are shown as `—`, never as zero.
- “Full-screen” is an in-app Overview mode that fills the main window; native macOS full-screen remains available through window controls.
- Do not add third-party dependencies or a new persistence layer.

## Review Focus

- Schema migration from existing records: old records must load with nil timing/sample data and keep their counts/bytes.
- Retry semantics: retries update the same record and must not inflate completed-download counts.
- Active/incomplete records: partial rows and summaries must not crash or display false zeroes.
- Date boundaries: local-day presets and inclusive custom end dates must bucket records consistently.
- Speed math: idle gaps must not lower active low/average values, and peak must come from real samples.

### Task 1: Add persisted analytics data and manager instrumentation

**Files:**
- Modify: `MacFetch/Models.swift`
- Modify: `MacFetch/DownloadManager.swift`

**Interfaces:**
- `DownloadRecord.startedAt: Date?`, `completedAt: Date?`, `peakSpeed: Double?`
- `DownloadSample` SwiftData model with `id`, `recordID`, `timestamp`, `downloadedBytes`, `speed`, and `stateRaw`
- `DownloadManager.samples: [DownloadSample]`
- `DownloadManager` records one sample per tick while active and sets timing/peak fields on lifecycle transitions.

- [ ] **Step 1: Extend `DownloadRecord` with optional lifecycle metrics**

Add the three optional properties with nil-safe initialization so existing SwiftData rows remain valid. Preserve current computed properties and state behavior.

- [ ] **Step 2: Add the `DownloadSample` SwiftData model**

Use a unique UUID and store the record UUID rather than a relationship so samples remain lightweight and resilient to record deletion. Include a state raw value for future filtering.

- [ ] **Step 3: Load and expose samples from `DownloadManager`**

Fetch samples sorted by timestamp in `refresh()`, add the model to the container schema in `MacFetchApp.swift`, and expose them as a published/readable array.

- [ ] **Step 4: Instrument start, tick, completion, failure, and cancellation**

Set `startedAt` only when a queued record enters downloading, update `peakSpeed` from each active tick, insert a sample for each active tick, and set `completedAt` on completed or failed terminal paths. Do not create a new analytics record on retry; reset timing fields when retrying.

- [ ] **Step 5: Build the app**

Run `xcodebuild -project MacFetch.xcodeproj -scheme MacFetch -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/macfetch-derived build`.

Expected: BUILD SUCCEEDED, with existing app behavior compiling against the expanded SwiftData schema.

### Task 2: Build the pure analytics aggregation layer

**Files:**
- Create: `MacFetch/DownloadAnalytics.swift`

**Interfaces:**
- `enum AnalyticsMetric: String, CaseIterable { case downloads, data, speed }`
- `enum AnalyticsRange: Equatable { case today, days(Int), custom(Date, Date) }`
- `struct AnalyticsPoint: Identifiable { let date: Date; let value: Double; let label: String }`
- `struct AnalyticsSummary { completedCount: Int; startedCount: Int; totalBytes: Int64; averageSpeed: Double?; peakSpeed: Double?; lowSpeed: Double?; successRate: Double?; averageDuration: TimeInterval?; mostActiveDate: Date? }`
- `struct DownloadAnalytics { static func summarize(records:samples:range:calendar:) -> AnalyticsSummary; static func points(records:samples:range:metric:calendar:) -> [AnalyticsPoint] }`

- [ ] **Step 1: Define range normalization and bucket policy**

Normalize presets/custom ranges to local start/end dates. Use hourly buckets for Today, daily buckets for 7 days and 30 days, and daily/weekly buckets for longer custom ranges so chart points remain readable.

- [ ] **Step 2: Implement record inclusion and summary rules**

Count unique records started in range for `startedCount`; count records completed in range for `completedCount`; include records with known dates and sizes in total bytes; calculate success rate as completed divided by started; omit unavailable duration/speed values.

- [ ] **Step 3: Implement speed calculations**

Use positive-delta samples only. Calculate average speed as total observed bytes divided by total observed active time; low and peak are min/max of active sample speeds; return nil when there are no valid samples.

- [ ] **Step 4: Implement chart points for Downloads, Data, and Speed**

Downloads returns counts per bucket, Data returns bytes per bucket, and Speed returns the average active speed per bucket. Use stable bucket dates and zero values only for buckets inside the selected range with no event for count/data metrics; omit speed buckets with no valid sample.

- [ ] **Step 5: Type-check the isolated analytics source**

Run `xcrun swiftc -typecheck MacFetch/DownloadAnalytics.swift` if the local SDK permits standalone checking; otherwise rely on the full app build in Task 4.

### Task 3: Add Overview navigation and dashboard UI

**Files:**
- Modify: `MacFetch/ContentView.swift`
- Create: `MacFetch/AnalyticsDashboardView.swift`

**Interfaces:**
- `ContentView` owns an `AppSection` selection with `.overview` and `.downloads`, and switches the main content while retaining existing filters/list/detail behavior.
- `AnalyticsDashboardView` accepts the environment `DownloadManager`, owns range/metric state, and renders the dashboard from `DownloadAnalytics`.

- [ ] **Step 1: Add Overview/Downloads navigation state**

Add an Overview item at the top of the sidebar, keep the current filter list below a divider, and make the existing list/detail column render only for Downloads. Preserve search, selection, bulk actions, drop-to-download, and add-download behavior.

- [ ] **Step 2: Build the dashboard header and range controls**

Create a full-window dashboard with title, subtitle, add-download button, a range picker for Today/7 days/30 days/Custom, and a metric picker for Downloads/Data/Speed. Use native controls and accessible labels.

- [ ] **Step 3: Add KPI cards and insights**

Show completed downloads, total data, average speed, peak speed, low speed, success rate, average duration, and most active period. Render unavailable values as `—` and use warning styling for failure/low-success insights.

- [ ] **Step 4: Add the primary native Chart**

Use `Chart` with `AreaMark`/`LineMark` appropriate to the metric, format bytes/speed/count axes, and add point tooltips through `chartOverlay` or native selection if available. The chart must update when range or metric changes.

- [ ] **Step 5: Add recent activity table and empty state**

List the latest records in range with file name, type, size, duration, average/peak speed where available, and status. Show a useful empty state with an Add download action when there is no history.

### Task 4: Integrate, verify, and polish

**Files:**
- Modify: `MacFetch/MacFetchApp.swift` if schema registration was not completed in Task 1
- Modify: `README.md` with the new Overview/history capability

- [ ] **Step 1: Build Debug and Release configurations**

Run both the Debug build from Task 1 and the documented Release build. Expected: BUILD SUCCEEDED for both.

- [ ] **Step 2: Review SwiftUI behavior statically**

Confirm the dashboard has a path with zero records, old records with nil timing values, active records, failed records, and a custom range whose end date is today. Confirm all four existing download actions remain reachable.

- [ ] **Step 3: Run the app for a smoke test if a macOS UI session is available**

Open Overview, switch presets and metrics, start a local test download, return to Downloads, and confirm that the dashboard updates after the transfer. If UI launch is unavailable, report that limitation and retain build verification as the evidence.

- [ ] **Step 4: Update README and inspect the diff**

Document Overview, historical ranges, speed metrics, and persistence. Run `git diff --check` and review `git diff --stat` for unintended files.

- [ ] **Step 5: Commit the completed feature**

Run `git add docs MacFetch README.md MacFetch.xcodeproj/project.pbxproj && git commit -m "feat: add download analytics dashboard"` after verification passes.

