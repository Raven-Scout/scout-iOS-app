# CLAUDE.md

Working notes for AI agents in this repo. Read `README.md` first for architecture,
features, and the desktop↔iOS mapping — this file only covers the operational
gotchas that aren't obvious from the source and that will bite you otherwise.

Scout-iOS is a read-mostly iPhone client over a Scout vault (markdown + `.scout-logs/`)
that lives in iCloud Obsidian. SwiftUI app, no backend.

## Build / test environment (read this before any xcodebuild)

**1. `xcode-select` points at CommandLineTools, not Xcode.** Every `xcodebuild`/`xcrun`
invocation must export the full Xcode first, or it fails to find the iOS SDK:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
```

**2. Simulator:** iPhone 17 Pro / iOS 26.5 is the known-good destination.

**3. `xcodebuild test` fails out of the box — the README command is incomplete.**
`project.yml` sets `GENERATE_INFOPLIST_FILE: false` globally and the test bundles have
no `Info.plist`, so a plain `test` errors with *"Cannot code sign because the target
does not have an Info.plist file."* Pass `CODE_SIGNING_ALLOWED=NO` and scope to the unit
target (the UITests target needs a booted sim + a real vault and will otherwise drag the
run down):

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
xcodebuild test \
  -project ScoutMobile.xcodeproj -scheme ScoutMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ScoutMobileTests \
  CODE_SIGNING_ALLOWED=NO
```

Filter the firehose with `| grep -iE "Test Case|passed|failed|error:|✔|✘|Suite"`.

## Project is generated — never hand-edit the .xcodeproj

This is an **XcodeGen** project. `ScoutMobile.xcodeproj/project.pbxproj` is generated
from `project.yml` and will be clobbered; editing it (e.g. to register a new file) is
wasted effort.

- Sources are **globbed by folder**: `ScoutMobile/**`, `ScoutMobileTests/**` (excluding
  `Fixtures/`), `ScoutMobileUITests/**`. Just drop a new `.swift` file in the right
  folder and run `xcodegen generate` — it gets picked up automatically.
- After adding/removing/renaming files, always `xcodegen generate` before building.
- To change targets, settings, Info.plist keys, or the scheme, edit `project.yml`.

## Tests

- Framework is **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.
  Match the existing style; construct models with their memberwise init and reach
  internals via `@testable import ScoutMobile`.
- `ParserContractTests` validates `Fixtures/parser-corpus.json`, shared byte-for-byte
  with the desktop app and the Python plugin. The line-level action-items parser must
  agree across all three — if you touch `Parsing/ActionItemsParser.swift`, expect this
  to be the contract you're held to. Don't "fix" the corpus to make a test pass.
- Fixtures include real anonymized `.scout-logs` and `usage-tracker.jsonl` — prefer
  adding a fixture over inlining log strings.

## Editor diagnostics lie; the build is the source of truth

SourceKit analyzes files in isolation without module context, so editing any file
shows spurious errors like *"Cannot find type 'Run' in scope"* / *"No such module
'Testing'"* even on unchanged lines. Ignore them. Verify with an actual `xcodebuild`.

## Code conventions worth knowing

- **Duration / date formatting is centralized.** `TimeInterval.compactDuration` and
  `Date.shortTime`/`dayLabel` live as extensions in
  `Views/Components/DesignSystem.swift` and are visible module-wide. Reuse them — do not
  hand-roll `"\(Int(d/60))m..."` strings. (A hand-rolled formatter that never rolled
  minutes into hours is exactly why a 10h run once notified as "601m 6s".)
- Layering: `Models` → `Parsing` → `Services`/`Vault` → `Views`/`App`. Services may use
  the Foundation-only helpers from `DesignSystem.swift`, but keep SwiftUI out of the
  lower layers.
- iOS has no git and no `scoutctl`: mutations are direct, line-targeted markdown edits
  via `NSFileCoordinator`, re-locating the task by its stable `[#TAG]` prefix rather
  than trusting parse-time line numbers (Scout rewrites files between parses).

## Debugging against real data

The live vault is readable on this Mac for diagnosing parsing/format bugs against actual
logs (this is how the duration bug was confirmed):

```
~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Scout/.scout-logs/
```

Finish markers look like:
`=== Scout Dreaming run finished at <date> (exit code: 0, duration: 36066s) ===`
`SessionLogParser` reads `durationSeconds` from that marker; the duration value is the
runner's wall-clock, which the app reports faithfully.

Behavioral note: notifications fire when the app **polls and detects** a newly-finished
run (foreground timer / BGAppRefreshTask), *not* at the run's finish time — so a
notification timestamp can lag the actual completion by hours.
