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

## Fixtures must be anonymized — this repo and both siblings are public

The live vault is a real person's work data (see "Debugging against real data"), so
anything lifted from it into a fixture (or an inline test string) **must be scrubbed
before it lands**. All three Scout repos are public on GitHub.

- **No real identifiers.** Strip company/product names, real coworker names, real Linear
  IDs, GitHub repos, and Slack workspaces/channels. Use the established stand-ins so
  fixtures stay internally consistent:
  - People: `Alex` / `Priya` / `Sam`; comment/proposal author `alex` / `Alex`.
  - Linear: `PROJ-1234` — never the real team prefixes (`AI-`, `KAI-`, `ST-`, …).
  - GitHub: `example-org/example-repo`.
  - Slack: `example.slack.com/archives/C0123456789/p1700000000000000`.
  - Vendors/products: a generic noun ("the demo", "the tracing job"), not the brand.
- **Anonymize content, not structure.** Keep the load-bearing tokens the parser is
  actually tested on — the synthetic `[#TAG]` short-prefixes (`MIRO`, `AI3026`, `RSM`,
  `5864M`…), `**bold**`, `_(italic)_`, `[[wikilinks]]`, ` — ` separators, `` `code` ``.
  Only swap the words around them. Tags like `MIRO`/`AI3026` are chosen for their letters
  (they exercise the non-Crockford `I`/`O` path), so don't rename them.

### `parser-corpus.json` is ONE byte-identical file living in three repos

It is the cross-language parser contract, checksum-guarded on two sides, so you cannot
edit just one copy. On any change (anonymizing counts):

1. Edit `ScoutMobileTests/Fixtures/parser-corpus.json`; keep every `expected` field
   consistent with the parser rules (`ParserContractTests` is the judge).
2. Copy it byte-for-byte into the siblings (clones sit next to this repo under `../`):
   - `../Scout/ScoutTests/Fixtures/parser-corpus.json` (desktop app)
   - `../scout-plugin/engine/tests/fixtures/contract/parser-corpus.json` (the canonical copy)
3. Update BOTH checksum guards to the new `shasum -a 256` of the file:
   - `canonicalSHA256` in `../Scout/ScoutTests/ActionItems/ParserContractTests.swift`
   - `EXPECTED_SHA256` in `../scout-plugin/engine/tests/unit/test_parser_corpus_checksum.py`
4. Verify all three sides: scout-ios `ParserContractTests`; desktop
   `-only-testing:ScoutTests/ParserContractTests` on `platform=macOS`; plugin
   `pytest tests/unit/test_parser_contract.py tests/unit/test_parser_corpus_checksum.py`.

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

## SwiftUI nav-bar gotchas (segmented picker + toolbar buttons)

Both of these bit us hard on the Ideas tab (`Views/Ideas/IdeasScreen.swift`).
`ActivityScreen` is the reference for "doing it right" — copy its shape for any
new tab with a nav-bar segmented control.

- **A segmented `Picker` in `ToolbarItem(placement: .principal)` collapses its
  segments onto one spot for a frame on every selection change UNLESS the
  `NavigationStack` registers a `.navigationDestination(...)`.** Without one, the
  stack destructively re-lays-out the principal item when the content swaps,
  re-running the bridged `UISegmentedControl` layout. It's only *visible* with ≥3
  segments — two short ones (Sessions/Schedule) reflow imperceptibly, which is the
  only reason `ActivityScreen` looked fine. `ActivityScreen` is stable because it
  registers a real `Run` destination; `IdeasScreen` has no detail navigation so it
  registers a **no-op** `navigationDestination(for: IdeasNoNavigation.self)`. Add a
  destination to any new segmented-picker-in-the-nav-bar screen. The defect is in
  UIKit's nav-bar title compatibility path (`_UITAMICAdaptorView`; Apple DTS
  forum 712461), so SwiftUI-layer fixes do **not** work — `.id()`,
  `.animation(nil)`, `Transaction(disablesAnimations:)`, `.fixedSize()`, a fixed
  `.frame(width:)`, or a constant title all still glitch, and even a
  UIViewRepresentable-hosted `UISegmentedControl` collapses (it's re-created on
  each content swap). Don't reach for a hand-rolled custom segmented control —
  the `navigationDestination` keeps the real system control.

- **A `ToolbarItem` button hosted *inside* a view that gets swapped out on a pane
  switch needs two taps** — the first is absorbed because the button's hit-test
  frame is corrupted while the bar re-lays out (separate Apple defect; SO 63540602).
  Keep toolbar buttons and their `.sheet` at the stable `NavigationStack` level,
  not in the swapped child, and present with `.sheet(item:)`. This is why
  `IdeasScreen` owns the ＋ Add button/sheet rather than `PerFileListView`.

## Verifying one-frame UI glitches

Sub-second SwiftUI glitches don't show up in unit tests and are easy to misjudge.
Drive the interaction from a throwaway UITest (set `SCOUT_VAULT_PATH` in
`app.launchEnvironment`, tap with `sleep`s between taps; make tappable controls
real `Button`s so XCUITest can find them), record the sim, and frame-step:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
xcrun simctl io "iPhone 17 Pro" recordVideo --codec h264 --force out.mov &   # SIGINT (kill -INT) to finalize the .mov
# run the probe with `xcodebuild test-without-building -only-testing:...` while it records, then stop the recording
ffmpeg -i out.mov -vf "crop=in_w:in_h*0.085:0:in_h*0.045,select='gt(scene,0.012)'" -vsync vfr f_%03d.png
```

Judge by the **full-resolution frames**, never a frame *count* — scene-change
counts are confounded by the nav title and selection highlight changing, which
burned us with false positives/negatives. Two more traps: a UITest that fails
early (short recording) looks "glitch-free" because no transition happened —
always confirm the panes actually switched; and XCUITest's synthetic taps can't
reproduce real-device "first tap absorbed" (double-tap) bugs — those need a
physical device to verify.

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
