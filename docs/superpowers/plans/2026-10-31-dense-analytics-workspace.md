# Dense Analytics Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a linked, filterable Analytics workspace with comparison deltas, coordinated charts, a dense activity table, and CSV export.

**Architecture:** Extend the pure `DownloadAnalytics` layer with a value-based workspace filter/snapshot model. The snapshot will derive filtered records, comparison metrics, breakdown buckets, speed statistics, and CSV rows from the existing `DownloadRecord` and `DownloadSample` arrays. Add a dedicated SwiftUI workspace view that owns only UI selection state and renders every panel from that snapshot.

**Tech Stack:** Swift 5, SwiftUI, SwiftData models already present, Charts, macOS 14 SDK, native file export/save panel APIs.

**Spec:** `docs/superpowers/specs/2026-10-31-dense-analytics-workspace-design.md`

## Global Constraints

- No draggable dashboard builder, saved layouts, cloud sync, accounts, or remote analytics.
- No changes to download execution, queue scheduling, throttling, or browser capture behavior.
- Time ranges use the same local-calendar and inclusive-end-day rules as Overview.
- Source domain is lower-case `URL.host`, with `Local file` for missing/invalid hosts.
- Paused is its own status; “In progress” groups only downloading and queued.
- CSV is UTF-8, comma-separated, and quotes fields containing commas, quotes, or newlines.
- Existing Overview, Downloads, detail, menu-bar, and Chrome workflows remain available.

## Review Focus

- Filter composition: every KPI, chart, and table must use the same filtered record set.
- Previous-period comparison: equal-duration ranges must not leak current-period records.
- Zero baselines: deltas must show “New” rather than divide by zero.
- Missing samples: speed stats and charts must show `—`/empty rather than fake zeroes.
- CSV escaping: commas, quotes, newlines, and non-ASCII filenames must round-trip as valid CSV.

### Task 1: Add the pure linked analytics model

**Files:**
- Modify: `MacFetch/DownloadAnalytics.swift`

**Interfaces:**
- `enum AnalyticsBreakdown { case fileType, sourceDomain }`
- `struct AnalyticsWorkspaceFilter: Equatable { var range: AnalyticsRange; var fileTypes: Set<String>; var statuses: Set<String>; var domains: Set<String>; var selectedBucket: Date?; var breakdown: AnalyticsBreakdown }`
- `struct AnalyticsDelta { let absolute: Double; let percentage: Double? }`
- `struct AnalyticsWorkspaceSnapshot { let records: [DownloadRecord]; let summary: AnalyticsSummary; let previousSummary: AnalyticsSummary; let deltas: [String: AnalyticsDelta]; let breakdown: [(label: String, value: Double)]; let speedMedian: Double?; let speedValues: [Double]; let csv: String }`
- `DownloadAnalytics.workspaceSnapshot(records:samples:filter:calendar:) -> AnalyticsWorkspaceSnapshot`
- `DownloadAnalytics.sourceDomain(for:) -> String`

- [ ] **Step 1: Add the failing contract fixture**

Create a temporary source-level contract fixture that references the new filter, snapshot, source-domain, and CSV APIs; run the available parser/typecheck command and record the environment limitation if full Swift typechecking is unavailable.

- [ ] **Step 2: Implement source-domain and status normalization helpers**

Normalize URL hosts lower-case, return `Local file` when unavailable, and expose paused separately while retaining existing state labels.

- [ ] **Step 3: Implement filtered-record composition**

Apply range, selected bucket, file type, status, and domain filters in that order. Treat “In progress” as downloading or queued only. The returned records are the single source for all snapshot panels.

- [ ] **Step 4: Implement previous-period comparison and deltas**

Create the immediately preceding equal-duration range, calculate current/previous summaries with the same metric rules, and return absolute plus percentage deltas. Use nil percentage when the previous value is zero; the UI renders that as “New”.

- [ ] **Step 5: Implement breakdowns and speed distribution**

Return file-type or source-domain values using received bytes by default, collect positive active samples for filtered records, and calculate median alongside existing average/peak/low values.

- [ ] **Step 6: Implement stable CSV serialization**

Emit the exact columns `date`, `file_name`, `file_type`, `source_domain`, `status`, `bytes_received`, `duration_seconds`, `average_speed_bytes_per_second`, with local ISO-8601 dates and empty cells for unavailable metrics. Escape CSV fields according to RFC 4180-style quoting.

- [ ] **Step 7: Run parser and whitespace checks**

Run `xcrun swiftc -frontend -parse MacFetch/DownloadAnalytics.swift` and `git diff --check`; expected: both exit successfully.

### Task 2: Build the dense Analytics workspace UI

**Files:**
- Create: `MacFetch/AnalyticsWorkspaceView.swift`
- Modify: `MacFetch/ContentView.swift`
- Modify: `MacFetch.xcodeproj/project.pbxproj`

**Interfaces:**
- `AnalyticsWorkspaceView` accepts `onOpenRecord: (DownloadRecord) -> Void` and `onExport: (String) -> Void` callbacks, reads `DownloadManager`, and renders `AnalyticsWorkspaceSnapshot`.

- [ ] **Step 1: Add Analytics sidebar navigation**

Add an Analytics destination beside Overview and Downloads. When selected, hide the legacy detail column using the same main-window column visibility behavior as Overview.

- [ ] **Step 2: Add the shared filter rail**

Render range controls, multi-select menus for file type/status/domain, breakdown toggle, selected-bucket chips, and Clear filters. All controls update one `AnalyticsWorkspaceFilter` state.

- [ ] **Step 3: Add comparison KPI cards**

Render downloads, data, average speed, and success rate with absolute and percentage deltas. Use “New” for zero-baseline percentage comparisons and `—` for unavailable speed metrics.

- [ ] **Step 4: Add coordinated charts**

Render volume over time, speed distribution (average/median/peak/low), outcomes, and file-type/source-domain breakdown. Chart selection updates `selectedBucket` or a breakdown filter and shows a removable chip.

- [ ] **Step 5: Add the linked activity table**

Use native `Table` to render date, file, type, source, status, received size, duration, and average speed. Selecting a row calls `onOpenRecord`.

- [ ] **Step 6: Add empty/loading states and narrow-window behavior**

Provide useful zero-history and zero-filter-match states. Collapse panels into a single scroll column when the available width is narrow enough to avoid unreadable dense columns.

- [ ] **Step 7: Register the new Swift file and run parser checks**

Add `AnalyticsWorkspaceView.swift` to the Xcode project and run parser checks for it and `ContentView.swift`.

### Task 3: Wire detail presentation, export, and documentation

**Files:**
- Modify: `MacFetch/ContentView.swift`
- Modify: `MacFetch/MacFetchApp.swift` only if a shared file-export helper is needed
- Modify: `README.md`

- [ ] **Step 1: Present table-row detail from Analytics**

Use a sheet or existing detail presentation to show the selected `DownloadRecord` without navigating away from Analytics; keep Downloads’ existing detail behavior unchanged.

- [ ] **Step 2: Add native CSV save behavior**

Present a save panel for the generated UTF-8 CSV, defaulting to `macfetch-analytics.csv`, and surface cancellation without error UI.

- [ ] **Step 3: Document Analytics**

Update README feature bullets and usage notes for linked filters, comparison deltas, and CSV export.

- [ ] **Step 4: Run final static verification**

Run parser checks for all changed Swift files, `plutil -lint MacFetch.xcodeproj/project.pbxproj`, and `git diff --check`. Attempt the documented Debug build; if full Xcode is still unavailable, report that exact limitation.

- [ ] **Step 5: Review the final diff**

Confirm the Analytics destination is reachable, every panel derives from one snapshot, CSV columns match the contract, and no downloader behavior changed.

