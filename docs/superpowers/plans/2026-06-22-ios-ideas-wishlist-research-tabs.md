# iOS "Ideas" tab (Proposals + Wishlist + Research) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-file Wishlist and Research lists to Scout-iOS and merge them with the existing Proposals tab into one segmented "Ideas" section (view + add + resolve), porting [Raven-Scout/Scout#40](https://github.com/Raven-Scout/Scout/pull/40).

**Architecture:** Port the desktop's generalized per-file module to iOS, adapted to iOS's polling / no-git / `NSFileCoordinator` world. Wishlist and Research are two `PerFileTabConfig` *values*, not new types. Proposals keeps its own single-file data layer; only its body renderer and list body are generalized for reuse. A new `IdeasScreen` container hosts three panes behind a segmented `Picker`, exactly like `ActivityScreen` hosts Sessions/Schedule.

**Tech Stack:** Swift, SwiftUI, Swift Testing, XcodeGen, `NSFileCoordinator` (iCloud-coordinated I/O). No backend, no git on device.

## Global Constraints

- **XcodeGen project — never hand-edit `.xcodeproj`.** Sources are globbed by folder. After creating/moving/deleting any `.swift` file, run `xcodegen generate` before building. Edit `project.yml` for target/scheme/Info.plist changes.
- **Build/test environment:** every `xcodebuild`/`xcodegen` invocation must first `export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer`.
- **Simulator destination:** `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5`.
- **Test command** (unit target only, no code signing):
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
  xcodebuild test -project ScoutMobile.xcodeproj -scheme ScoutMobile \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    -only-testing:ScoutMobileTests CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -iE "Test Case|passed|failed|error:|✔|✘|Suite"
  ```
  Scope to one suite by appending the suite name, e.g. `-only-testing:ScoutMobileTests/PerFileItemParserTests`.
- **Build-only check** (for presentational tasks):
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
  xcodebuild build -project ScoutMobile.xcodeproj -scheme ScoutMobile \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE "error:|warning:|BUILD (SUCCEEDED|FAILED)"
  ```
- **Editor diagnostics lie** — SourceKit shows spurious "Cannot find type" / "No such module 'Testing'" errors. Trust `xcodebuild`, not the editor.
- **Tests are Swift Testing:** `import Testing`, `@Suite`, `@Test`, `#expect`, `#require`; `@testable import ScoutMobile`. Construct models with their memberwise init.
- **Layering:** `Models → Parsing → Services/Vault → Views`. Keep SwiftUI out of Models/Parsing/Services/Vault.
- **Per-file data contract is fixed** (byte-for-byte with desktop + scout-plugin): frontmatter keys `title` (quoted), `status` (`open`/`in-progress`/`done`/`dropped`), `priority` (`urgent`/`high`/`medium`/`low`), `date` (`yyyy-MM-dd`), optional `source` (wishlist) / `area` (research); body is `# Title` + markdown. File names are `YYYY-MM-DD-slug.md`. Directories: `docs/wishlist`, `knowledge-base/research-queue`. Do not invent new keys.
- **No git writes on iOS.** New files are created and status flips happen through `VaultAccess` (coordinated). iCloud/Obsidian propagate.
- **Commits:** Conventional Commits. Do **not** add `Co-Authored-By` or "Generated with Claude Code" lines (user's global rule).
- **Branch:** `adamvyborny-ideas-tab` (already created off `main`).
- **New test files** go under `ScoutMobileTests/PerFile/`.

---

### Task 1: Item status & priority enums

**Files:**
- Create: `ScoutMobile/Models/ItemStatus.swift`
- Create: `ScoutMobile/Models/ItemPriority.swift`
- Test: `ScoutMobileTests/PerFile/ItemStatusPriorityTests.swift`

**Interfaces:**
- Produces: `enum ItemStatus { case open, inProgress, done, dropped, unknown(String) }` with `static func parse(_:) -> ItemStatus`, `var isActive: Bool`, `var displayName: String`, `var frontmatterValue: String`.
- Produces: `enum ItemPriority: String, Comparable, CaseIterable { case urgent, high, medium, low }` with `static func parse(_:) -> ItemPriority`, `var displayName: String`.

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/ItemStatusPriorityTests.swift`:

```swift
import Testing
@testable import ScoutMobile

@Suite("ItemStatus")
struct ItemStatusTests {
    @Test func parsesKnownValuesCaseInsensitively() {
        #expect(ItemStatus.parse("open") == .open)
        #expect(ItemStatus.parse("In-Progress") == .inProgress)
        #expect(ItemStatus.parse("in progress") == .inProgress)
        #expect(ItemStatus.parse("done") == .done)
        #expect(ItemStatus.parse("dropped") == .dropped)
        #expect(ItemStatus.parse("") == .open)
    }

    @Test func unknownIsPreservedVerbatim() {
        #expect(ItemStatus.parse("blocked") == .unknown("blocked"))
    }

    @Test func activeMeansOpenOrInProgress() {
        #expect(ItemStatus.open.isActive)
        #expect(ItemStatus.inProgress.isActive)
        #expect(!ItemStatus.done.isActive)
        #expect(!ItemStatus.dropped.isActive)
        #expect(!ItemStatus.unknown("x").isActive)
    }

    @Test func frontmatterValueRoundTrips() {
        #expect(ItemStatus.inProgress.frontmatterValue == "in-progress")
        #expect(ItemStatus.done.frontmatterValue == "done")
        #expect(ItemStatus.parse(ItemStatus.dropped.frontmatterValue) == .dropped)
    }
}

@Suite("ItemPriority")
struct ItemPriorityTests {
    @Test func parsesAndDefaultsToMedium() {
        #expect(ItemPriority.parse("urgent") == .urgent)
        #expect(ItemPriority.parse("HIGH") == .high)
        #expect(ItemPriority.parse("low") == .low)
        #expect(ItemPriority.parse("") == .medium)
        #expect(ItemPriority.parse("bogus") == .medium)
    }

    @Test func ordersUrgentFirst() {
        #expect([ItemPriority.low, .urgent, .medium, .high].sorted() == [.urgent, .high, .medium, .low])
    }

    @Test func displayNameIsCapitalized() {
        #expect(ItemPriority.urgent.displayName == "Urgent")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (test command, scoped):
```bash
... -only-testing:ScoutMobileTests/ItemStatusTests
```
Expected: FAIL — compile error "Cannot find 'ItemStatus' in scope" (types don't exist yet). (After creating the files in Step 3 you must `xcodegen generate` so the test target sees them.)

- [ ] **Step 3: Create the implementations**

Create `ScoutMobile/Models/ItemStatus.swift`:

```swift
import Foundation

/// Lifecycle of a per-file Wishlist/Research item (frontmatter `status:`).
enum ItemStatus: Equatable, Sendable {
    case open, inProgress, done, dropped, unknown(String)

    static func parse(_ raw: String) -> ItemStatus {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "open", "": return .open
        case "in-progress", "in progress", "inprogress": return .inProgress
        case "done": return .done
        case "dropped": return .dropped
        default: return .unknown(trimmed)
        }
    }

    /// open/in-progress are active (Awaiting); done/dropped/unknown are resolved.
    var isActive: Bool {
        switch self {
        case .open, .inProgress: return true
        case .done, .dropped, .unknown: return false
        }
    }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .dropped: return "Dropped"
        case .unknown(let raw): return raw
        }
    }

    /// The exact value written back into frontmatter.
    var frontmatterValue: String {
        switch self {
        case .open: return "open"
        case .inProgress: return "in-progress"
        case .done: return "done"
        case .dropped: return "dropped"
        case .unknown(let raw): return raw
        }
    }
}
```

Create `ScoutMobile/Models/ItemPriority.swift`:

```swift
import Foundation

/// Priority of a per-file item. Wishlist uses high/medium/low; Research adds urgent.
enum ItemPriority: String, Equatable, Sendable, Comparable, CaseIterable {
    case urgent, high, medium, low

    static func parse(_ raw: String) -> ItemPriority {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "urgent": return .urgent
        case "high": return .high
        case "low": return .low
        default: return .medium   // "medium", missing, or unrecognized
        }
    }

    private var rank: Int {
        switch self { case .urgent: return 0; case .high: return 1; case .medium: return 2; case .low: return 3 }
    }
    static func < (lhs: ItemPriority, rhs: ItemPriority) -> Bool { lhs.rank < rhs.rank }

    var displayName: String { rawValue.capitalized }
}
```

- [ ] **Step 4: Regenerate the project and run the tests**

Run:
```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
xcodegen generate
```
Then the test command scoped to `-only-testing:ScoutMobileTests/ItemStatusTests -only-testing:ScoutMobileTests/ItemPriorityTests`.
Expected: PASS — all status & priority tests green.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Models/ItemStatus.swift ScoutMobile/Models/ItemPriority.swift \
        ScoutMobileTests/PerFile/ItemStatusPriorityTests.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add ItemStatus and ItemPriority models"
```

---

### Task 2: Generalize the markdown body renderer (refactor)

Extracts the shared body model + view out of Proposals so all three panes reuse them. Pure rename/move under existing green tests — no behavior change.

**Files:**
- Create: `ScoutMobile/Models/MarkdownBodyBlock.swift` (moved out of `Proposal.swift`)
- Modify: `ScoutMobile/Models/Proposal.swift` (remove the `ProposalBodyBlock` enum; point `bodyBlocks` at `MarkdownBodyBlock`)
- Move/rename: `ScoutMobile/Views/Proposals/ProposalBodyView.swift` → `ScoutMobile/Views/Components/MarkdownBodyView.swift`
- Modify: `ScoutMobile/Views/Proposals/ProposalCardView.swift` (`ProposalBodyView` → `MarkdownBodyView`)

**Interfaces:**
- Produces: `enum MarkdownBodyBlock: Equatable, Sendable, Identifiable { case prose(String); case code(language: String?, code: String) }` with `static func blocks(from: String) -> [MarkdownBodyBlock]`.
- Produces: `struct MarkdownBodyView: View { let blocks: [MarkdownBodyBlock] }`.

- [ ] **Step 1: Confirm existing tests are green (baseline)**

Run the test command scoped to `-only-testing:ScoutMobileTests/ProposalsParserTests`.
Expected: PASS (4-proposal fixture, code-fence block test). This is the safety net for the refactor.

- [ ] **Step 2: Create `MarkdownBodyBlock.swift`**

Create `ScoutMobile/Models/MarkdownBodyBlock.swift`:

```swift
import Foundation

/// A structural block of a markdown body: prose paragraphs (inline markdown)
/// and verbatim fenced code blocks. Shared by Proposals and per-file items so
/// dense bold-label-and-code text renders readably instead of as one wall.
enum MarkdownBodyBlock: Equatable, Sendable, Identifiable {
    case prose(String)
    case code(language: String?, code: String)

    var id: String {
        switch self {
        case .prose(let t):          return "p:\(t)"
        case .code(let lang, let c): return "c:\(lang ?? ""):\(c)"
        }
    }

    /// Split a raw body into ordered blocks. Fenced code blocks (```` ``` ````)
    /// are lifted out verbatim; the prose between them is broken into paragraphs
    /// on blank lines.
    static func blocks(from rawBody: String) -> [MarkdownBodyBlock] {
        let lines = rawBody.components(separatedBy: "\n")
        var blocks: [MarkdownBodyBlock] = []
        var proseBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushProse() {
            let joined = proseBuffer.joined(separator: "\n")
            for para in paragraphs(in: joined) { blocks.append(.prose(para)) }
            proseBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                    inCode = false
                } else {
                    flushProse()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
                continue
            }
            if inCode { codeBuffer.append(line) } else { proseBuffer.append(line) }
        }

        if inCode { blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n"))) }
        flushProse()
        return blocks
    }

    private static func paragraphs(in text: String) -> [String] {
        text.components(separatedBy: "\n")
            .reduce(into: [[String]]()) { acc, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if acc.last?.isEmpty == false { acc.append([]) }
                } else {
                    if acc.isEmpty { acc.append([]) }
                    acc[acc.count - 1].append(line)
                }
            }
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 3: Strip the old enum from `Proposal.swift` and repoint `bodyBlocks`**

In `ScoutMobile/Models/Proposal.swift`:
1. Delete the entire `enum ProposalBodyBlock { … }` definition (the block starting at the `/// A structural block of a proposal body.` comment through the closing brace at end of file).
2. Change the `bodyBlocks` computed property on `Proposal` from:
   ```swift
   var bodyBlocks: [ProposalBodyBlock] { ProposalBodyBlock.blocks(from: bodyMarkdown) }
   ```
   to:
   ```swift
   var bodyBlocks: [MarkdownBodyBlock] { MarkdownBodyBlock.blocks(from: bodyMarkdown) }
   ```

- [ ] **Step 4: Move/rename the body view**

Move the file and rename the type:
```bash
git mv ScoutMobile/Views/Proposals/ProposalBodyView.swift ScoutMobile/Views/Components/MarkdownBodyView.swift
```
In `ScoutMobile/Views/Components/MarkdownBodyView.swift`:
- Rename `struct ProposalBodyView: View` → `struct MarkdownBodyView: View`.
- Change `let blocks: [ProposalBodyBlock]` → `let blocks: [MarkdownBodyBlock]`.
- Update the doc comment first line to: `/// Renders a markdown body as a vertical stack of prose paragraphs (inline`.

- [ ] **Step 5: Repoint the proposal card**

In `ScoutMobile/Views/Proposals/ProposalCardView.swift`, change the one call site:
```swift
            if !proposal.bodyBlocks.isEmpty {
                MarkdownBodyView(blocks: proposal.bodyBlocks)
            }
```

- [ ] **Step 6: Regenerate, build, and re-run the proposal tests**

Run:
```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
xcodegen generate
```
Then the test command scoped to `-only-testing:ScoutMobileTests/ProposalsParserTests` and the build-only check.
Expected: PASS (same 4-proposal tests) and `BUILD SUCCEEDED` — the rename is behavior-preserving.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(proposals): generalize body renderer to MarkdownBodyBlock/MarkdownBodyView"
```

---

### Task 3: PerFileItem model + parser

**Files:**
- Create: `ScoutMobile/Models/PerFileItem.swift`
- Create: `ScoutMobile/Parsing/PerFileItemParser.swift`
- Test: `ScoutMobileTests/PerFile/PerFileItemParserTests.swift`

**Interfaces:**
- Consumes: `ItemStatus`, `ItemPriority` (Task 1), `MarkdownBodyBlock` (Task 2).
- Produces: `struct PerFileItem: Identifiable, Equatable, Sendable` with `let relativePath: String`, `date`, `title`, `status: ItemStatus`, `priority: ItemPriority`, `source: String?`, `area: String?`, `bodyMarkdown: String`; `var id: String { relativePath }`, `var isActive: Bool`, `var bodyBlocks: [MarkdownBodyBlock]`.
- Produces: `enum PerFileItemParser { static func parseFile(contents: String, relativePath: String) -> PerFileItem? }` (+ pure helpers `splitFrontmatter`, `parseFrontmatterFields`, `stripLeadingHeading`, `datePrefix`).

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/PerFileItemParserTests.swift`:

```swift
import Testing
@testable import ScoutMobile

@Suite("PerFileItemParser")
struct PerFileItemParserTests {

    private let wishlistFixture = """
    ---
    title: "Faster cold start"
    status: open
    priority: high
    date: 2026-06-20
    source: "Slack #scout"
    ---

    # Faster cold start

    Cache the parsed config between launches.

    ```swift
    let cached = try Cache.load()
    ```
    """

    @Test func parsesFrontmatterAndBody() {
        let item = PerFileItemParser.parseFile(contents: wishlistFixture,
                                               relativePath: "docs/wishlist/2026-06-20-faster-cold-start.md")
        let unwrapped = try! #require(item)
        #expect(unwrapped.title == "Faster cold start")
        #expect(unwrapped.status == .open)
        #expect(unwrapped.priority == .high)
        #expect(unwrapped.date == "2026-06-20")
        #expect(unwrapped.source == "Slack #scout")
        #expect(unwrapped.area == nil)
        #expect(unwrapped.relativePath == "docs/wishlist/2026-06-20-faster-cold-start.md")
        // The leading `# Heading` is stripped; prose + code survive.
        #expect(!unwrapped.bodyMarkdown.hasPrefix("# "))
        #expect(unwrapped.bodyMarkdown.contains("Cache the parsed config"))
        let codeBlocks = unwrapped.bodyBlocks.compactMap { block -> String? in
            if case .code(_, let c) = block { return c } else { return nil }
        }
        #expect(codeBlocks.first == "let cached = try Cache.load()")
    }

    @Test func noFrontmatterYieldsNil() {
        #expect(PerFileItemParser.parseFile(contents: "# Just a doc\n\nNo frontmatter here.",
                                            relativePath: "docs/wishlist/readme.md") == nil)
    }

    @Test func fallsBackToFilenameForDateAndTitle() {
        let text = """
        ---
        status: in-progress
        priority: bogus
        ---

        Body only.
        """
        let item = try! #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "knowledge-base/research-queue/2026-06-19-oauth-pkce.md"))
        #expect(item.date == "2026-06-19")            // from filename prefix
        #expect(item.title == "2026-06-19-oauth-pkce") // from filename stem
        #expect(item.status == .inProgress)
        #expect(item.priority == .medium)             // unrecognized → medium
    }

    @Test func readsAreaForResearchItems() {
        let text = """
        ---
        title: "PKCE flow"
        status: open
        priority: urgent
        date: 2026-06-19
        area: "Auth"
        ---

        # PKCE flow

        Investigate.
        """
        let item = try! #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "knowledge-base/research-queue/2026-06-19-pkce-flow.md"))
        #expect(item.area == "Auth")
        #expect(item.source == nil)
        #expect(item.priority == .urgent)
        #expect(item.isActive)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemParserTests`.
Expected: FAIL — "Cannot find 'PerFileItemParser' in scope".

- [ ] **Step 3: Create the model**

Create `ScoutMobile/Models/PerFileItem.swift`:

```swift
import Foundation

/// One per-file Wishlist/Research item: YAML frontmatter + markdown body.
///
/// Identity is the vault-relative path — both the stable SwiftUI id and the
/// file the writer rewrites on resolve. (iOS resolves the security-scoped vault
/// root per operation, so we never hold an absolute URL the way desktop does.)
struct PerFileItem: Identifiable, Equatable, Sendable {
    let relativePath: String
    let date: String          // frontmatter `date:` or filename YYYY-MM-DD prefix
    let title: String         // frontmatter `title:` or filename stem
    let status: ItemStatus
    let priority: ItemPriority
    let source: String?       // wishlist provenance (optional)
    let area: String?         // research grouping (optional)
    let bodyMarkdown: String

    var id: String { relativePath }
    var isActive: Bool { status.isActive }
    var bodyBlocks: [MarkdownBodyBlock] { MarkdownBodyBlock.blocks(from: bodyMarkdown) }
}
```

- [ ] **Step 4: Create the parser**

Create `ScoutMobile/Parsing/PerFileItemParser.swift`:

```swift
import Foundation

/// Pure parser for one per-file item (YAML frontmatter + markdown body).
/// Ported from the desktop app (Scout/PerFileItems/PerFileItemParser.swift).
/// Returns nil when the file has no frontmatter (skips index/non-item files).
enum PerFileItemParser {
    static func parseFile(contents: String, relativePath: String) -> PerFileItem? {
        guard let (frontmatter, body) = splitFrontmatter(contents) else { return nil }
        let fields = parseFrontmatterFields(frontmatter)
        let stem = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension

        let date = fields["date"]?.nonEmpty ?? datePrefix(of: stem) ?? ""
        let title = fields["title"]?.nonEmpty ?? stem
        let status = ItemStatus.parse(fields["status"] ?? "")
        let priority = ItemPriority.parse(fields["priority"] ?? "")
        let source = fields["source"]?.nonEmpty
        let area = fields["area"]?.nonEmpty
        let cleanBody = stripLeadingHeading(body).trimmingCharacters(in: .whitespacesAndNewlines)

        return PerFileItem(relativePath: relativePath, date: date, title: title, status: status,
                           priority: priority, source: source, area: area, bodyMarkdown: cleanBody)
    }

    static func splitFrontmatter(_ text: String) -> (frontmatter: String, body: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var frontmatter: [String] = []
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let body = i + 1 < lines.count ? lines[(i + 1)...].joined(separator: "\n") : ""
                return (frontmatter.joined(separator: "\n"), body)
            }
            frontmatter.append(lines[i])
            i += 1
        }
        return nil
    }

    static func parseFrontmatterFields(_ frontmatter: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in frontmatter.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }

    static func stripLeadingHeading(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first, first.hasPrefix("# "), !first.hasPrefix("## ") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    static func datePrefix(of stem: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}"#) else { return nil }
        let ns = stem as NSString
        guard let m = re.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
```

- [ ] **Step 5: Regenerate and run the tests**

Run `xcodegen generate`, then the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemParserTests`.
Expected: PASS — all four parser tests green.

- [ ] **Step 6: Commit**

```bash
git add ScoutMobile/Models/PerFileItem.swift ScoutMobile/Parsing/PerFileItemParser.swift \
        ScoutMobileTests/PerFile/PerFileItemParserTests.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add PerFileItem model and PerFileItemParser"
```

---

### Task 4: PerFileTabConfig

**Files:**
- Create: `ScoutMobile/Models/PerFileTabConfig.swift`
- Test: `ScoutMobileTests/PerFile/PerFileTabConfigTests.swift`

**Interfaces:**
- Consumes: `ItemPriority` (Task 1).
- Produces: `struct PerFileTabConfig: Sendable, Equatable` with `title`, `priorities: [ItemPriority]`, `defaultPriority: ItemPriority`, `optionalField: OptionalField`, `addNoun: String`, `directory: String`; nested `enum OptionalField { case none; case source(label: String); case area(label: String); var label: String? }`; statics `.wishlist`, `.research`.

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/PerFileTabConfigTests.swift`:

```swift
import Testing
@testable import ScoutMobile

@Suite("PerFileTabConfig")
struct PerFileTabConfigTests {
    @Test func wishlistContract() {
        let c = PerFileTabConfig.wishlist
        #expect(c.title == "Wishlist")
        #expect(c.directory == "docs/wishlist")
        #expect(c.priorities == [.high, .medium, .low])   // no .urgent for wishlist
        #expect(c.defaultPriority == .medium)
        #expect(c.optionalField.label == "Source")
    }

    @Test func researchContract() {
        let c = PerFileTabConfig.research
        #expect(c.title == "Research")
        #expect(c.directory == "knowledge-base/research-queue")
        #expect(c.priorities == [.urgent, .high, .medium, .low])
        #expect(c.optionalField.label == "Area")
    }

    @Test func noneOptionalFieldHasNoLabel() {
        #expect(PerFileTabConfig.OptionalField.none.label == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command scoped to `-only-testing:ScoutMobileTests/PerFileTabConfigTests`.
Expected: FAIL — "Cannot find 'PerFileTabConfig' in scope".

- [ ] **Step 3: Create the config**

Create `ScoutMobile/Models/PerFileTabConfig.swift`:

```swift
import Foundation

/// Per-pane knobs that parameterize the shared per-file store, list, and writer.
/// Wishlist and Research are two *values* of this type, not two types.
struct PerFileTabConfig: Sendable, Equatable {
    enum OptionalField: Sendable, Equatable {
        case none
        case source(label: String)
        case area(label: String)
        var label: String? {
            switch self {
            case .none: return nil
            case .source(let l), .area(let l): return l
            }
        }
    }

    let title: String
    let priorities: [ItemPriority]
    let defaultPriority: ItemPriority
    let optionalField: OptionalField
    let addNoun: String          // e.g. "wishlist item" — used in Add copy
    let directory: String        // vault-relative directory of item files

    static let wishlist = PerFileTabConfig(
        title: "Wishlist",
        priorities: [.high, .medium, .low],
        defaultPriority: .medium,
        optionalField: .source(label: "Source"),
        addNoun: "wishlist item",
        directory: "docs/wishlist"
    )

    static let research = PerFileTabConfig(
        title: "Research",
        priorities: [.urgent, .high, .medium, .low],
        defaultPriority: .medium,
        optionalField: .area(label: "Area"),
        addNoun: "research topic",
        directory: "knowledge-base/research-queue"
    )
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run `xcodegen generate`, then the test command scoped to `-only-testing:ScoutMobileTests/PerFileTabConfigTests`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Models/PerFileTabConfig.swift \
        ScoutMobileTests/PerFile/PerFileTabConfigTests.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add PerFileTabConfig with wishlist and research presets"
```

---

### Task 5: VaultAccess — create a unique file in a subdirectory

The one new I/O capability: Add needs to create a new `.md` file in a directory that may not exist yet, inside the security scope. Today's `writeFile` neither creates intermediate directories nor avoids name collisions.

**Files:**
- Modify: `ScoutMobile/Vault/VaultAccess.swift` (add `createUniqueFile`)
- Test: `ScoutMobileTests/PerFile/VaultAccessCreateFileTests.swift`

**Interfaces:**
- Produces: `func createUniqueFile(inDirectory directoryRelativePath: String, baseName: String, ext: String = "md", contents: String) throws -> String` — returns the vault-relative path of the created file.

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/VaultAccessCreateFileTests.swift`:

```swift
import Testing
import Foundation
@testable import ScoutMobile

@Suite("VaultAccess.createUniqueFile")
struct VaultAccessCreateFileTests {

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-createfile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "vault-createfile-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    @Test func createsFileAndMissingDirectory() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rel = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                             baseName: "2026-06-22-hello", contents: "hi\n")
        #expect(rel == "docs/wishlist/2026-06-22-hello.md")
        let written = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)
        #expect(written == "hi\n")
    }

    @Test func collisionGetsNumericSuffix() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                               baseName: "2026-06-22-dup", contents: "a")
        let second = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                                baseName: "2026-06-22-dup", contents: "b")
        #expect(first == "docs/wishlist/2026-06-22-dup.md")
        #expect(second == "docs/wishlist/2026-06-22-dup-2.md")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command scoped to `-only-testing:ScoutMobileTests/VaultAccessCreateFileTests`.
Expected: FAIL — "Value of type 'VaultAccess' has no member 'createUniqueFile'".

- [ ] **Step 3: Add the method**

In `ScoutMobile/Vault/VaultAccess.swift`, inside the `// MARK: - Writes` section (after `writeFile(relativePath:data:)`), add:

```swift
    /// Create a new file with a collision-free name in `directoryRelativePath`,
    /// creating the directory (and any intermediates) if absent, and write
    /// `contents`. Returns the new vault-relative path. The base name is
    /// suffixed (`-2`, `-3`, …) until it does not collide with an existing file
    /// or its iCloud placeholder. Coordinated atomic write — same hygiene as
    /// `writeFile`. Used by the per-file Add flow; iOS has no git, so the file
    /// is simply written and iCloud/Obsidian propagate it.
    func createUniqueFile(
        inDirectory directoryRelativePath: String,
        baseName: String,
        ext: String = "md",
        contents: String
    ) throws -> String {
        try withVault { root in
            let dir = directoryRelativePath.isEmpty
                ? root
                : root.appendingPathComponent(directoryRelativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var name = "\(baseName).\(ext)"
            var url = dir.appendingPathComponent(name)
            var n = 2
            let fm = FileManager.default
            while fm.fileExists(atPath: url.path)
                || fm.fileExists(atPath: Self.placeholderURL(for: url).path) {
                name = "\(baseName)-\(n).\(ext)"
                url = dir.appendingPathComponent(name)
                n += 1
            }

            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { actualURL in
                do {
                    try Data(contents.utf8).write(to: actualURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordError { throw coordError }
            if let writeError { throw writeError }

            return directoryRelativePath.isEmpty ? name : "\(directoryRelativePath)/\(name)"
        }
    }
```

- [ ] **Step 4: Run the tests**

Run the test command scoped to `-only-testing:ScoutMobileTests/VaultAccessCreateFileTests`.
Expected: PASS — both file-creation tests green. (No `xcodegen generate` needed — no files added/removed.)

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Vault/VaultAccess.swift ScoutMobileTests/PerFile/VaultAccessCreateFileTests.swift
git commit -m "feat(vault): add createUniqueFile for per-file item creation"
```

---

### Task 6: PerFileItemsWriter

**Files:**
- Create: `ScoutMobile/Vault/PerFileItemsWriter.swift`
- Test: `ScoutMobileTests/PerFile/PerFileItemsWriterTests.swift`

**Interfaces:**
- Consumes: `ItemStatus`, `ItemPriority` (Task 1), `PerFileItem`, `PerFileItemParser` (Task 3), `PerFileTabConfig` (Task 4), `VaultAccess.createUniqueFile`/`modifyTextFile` (Task 5 + existing).
- Produces: `enum ItemResolution: Sendable, Equatable { case done, dropped; var status: ItemStatus }`.
- Produces: `enum PerFileItemsWriter` with `static func addItem(config:title:priority:body:optional:vault:now:) throws -> String`, `static func resolve(_:item:vault:) throws`, and pure helpers `slugify(_:maxWords:)`, `renderItemFile(title:status:priority:date:source:area:body:)`, `rewriteFrontmatterStatus(text:newStatusValue:)`. Nested `enum WriteError: LocalizedError, Equatable { case emptyTitle, frontmatterNotFound, statusFieldNotFound }`.

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/PerFileItemsWriterTests.swift`:

```swift
import Testing
import Foundation
@testable import ScoutMobile

@Suite("PerFileItemsWriter (pure)")
struct PerFileItemsWriterPureTests {
    @Test func slugifyLowercasesAndDashes() {
        #expect(PerFileItemsWriter.slugify("Faster Cold Start!") == "faster-cold-start")
        #expect(PerFileItemsWriter.slugify("OAuth/PKCE flow") == "oauth-pkce-flow")
    }

    @Test func slugifyCapsWordCount() {
        #expect(PerFileItemsWriter.slugify("one two three four five", maxWords: 3) == "one-two-three")
    }

    @Test func renderProducesParseableFrontmatter() {
        let text = PerFileItemsWriter.renderItemFile(
            title: "Cache config", status: .open, priority: .high, date: "2026-06-22",
            source: "Slack #scout", area: nil, body: "Some notes.")
        #expect(text.contains("title: \"Cache config\""))
        #expect(text.contains("status: open"))
        #expect(text.contains("priority: high"))
        #expect(text.contains("date: 2026-06-22"))
        #expect(text.contains("source: \"Slack #scout\""))
        #expect(!text.contains("area:"))
        #expect(text.contains("# Cache config"))
        // Round-trips through the parser.
        let item = try! #require(PerFileItemParser.parseFile(contents: text,
                                 relativePath: "docs/wishlist/2026-06-22-cache-config.md"))
        #expect(item.title == "Cache config")
        #expect(item.priority == .high)
        #expect(item.source == "Slack #scout")
    }

    @Test func rewriteFlipsOnlyTheStatusLine() throws {
        let text = """
        ---
        title: "X"
        status: open
        priority: medium
        date: 2026-06-22
        ---

        # X

        Body.
        """
        let out = try PerFileItemsWriter.rewriteFrontmatterStatus(text: text, newStatusValue: "done")
        #expect(out.contains("status: done"))
        #expect(!out.contains("status: open"))
        #expect(out.contains("priority: medium"))  // untouched
        #expect(out.contains("# X"))               // body untouched
    }

    @Test func rewriteThrowsWhenNoFrontmatter() {
        #expect(throws: PerFileItemsWriter.WriteError.self) {
            try PerFileItemsWriter.rewriteFrontmatterStatus(text: "no frontmatter", newStatusValue: "done")
        }
    }
}

@Suite("PerFileItemsWriter end-to-end (coordinated file writes)")
struct PerFileItemsWriterE2ETests {

    private static func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 22; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfile-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "perfile-writer-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    @Test func addThenResolveRoundTrips() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rel = try PerFileItemsWriter.addItem(
            config: .wishlist, title: "Faster cold start", priority: .high,
            body: "Cache the config.", optional: "Slack #scout",
            vault: vault, now: Self.fixedDate())
        #expect(rel == "docs/wishlist/2026-06-22-faster-cold-start.md")

        // Parse the written file: open + high + source captured.
        let text1 = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)!
        let item = try #require(PerFileItemParser.parseFile(contents: text1, relativePath: rel))
        #expect(item.status == .open)
        #expect(item.priority == .high)
        #expect(item.source == "Slack #scout")

        // Resolve to done; reparse reflects it.
        try PerFileItemsWriter.resolve(.done, item: item, vault: vault)
        let text2 = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)!
        let resolved = try #require(PerFileItemParser.parseFile(contents: text2, relativePath: rel))
        #expect(resolved.status == .done)
        #expect(!resolved.isActive)
    }

    @Test func emptyTitleThrows() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: PerFileItemsWriter.WriteError.self) {
            try PerFileItemsWriter.addItem(config: .wishlist, title: "   ", priority: .medium,
                                           body: "", optional: nil, vault: vault, now: Self.fixedDate())
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemsWriterPureTests`.
Expected: FAIL — "Cannot find 'PerFileItemsWriter' in scope".

- [ ] **Step 3: Create the writer**

Create `ScoutMobile/Vault/PerFileItemsWriter.swift`:

```swift
import Foundation

/// A resolution the app can write back to a per-file item.
enum ItemResolution: Sendable, Equatable {
    case done, dropped
    var status: ItemStatus { self == .done ? .done : .dropped }
}

/// Creates per-file items and resolves them, writing directly to the vault
/// (the iOS app has no scoutctl and no git — items are plain markdown that
/// dreaming/research sessions and Obsidian also read and write).
///
/// Add renders a `YYYY-MM-DD-slug.md` file via `VaultAccess.createUniqueFile`.
/// Resolve flips the frontmatter `status:` line in place via
/// `VaultAccess.modifyTextFile` — leaving every other byte identical, the same
/// line-targeted hygiene as `ProposalsWriter`.
enum PerFileItemsWriter {

    enum WriteError: LocalizedError, Equatable {
        case emptyTitle
        case frontmatterNotFound
        case statusFieldNotFound

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Give the item a title."
            case .frontmatterNotFound:
                return "This file has no frontmatter to update — it may have been edited elsewhere. Pull to refresh."
            case .statusFieldNotFound:
                return "This item has no status field to update."
            }
        }
    }

    // MARK: - Mutations

    /// Render and create a new item file. Returns its vault-relative path.
    @discardableResult
    static func addItem(
        config: PerFileTabConfig,
        title: String,
        priority: ItemPriority,
        body: String,
        optional: String?,
        vault: VaultAccess,
        now: Date = Date()
    ) throws -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw WriteError.emptyTitle }

        var source: String?
        var area: String?
        switch config.optionalField {
        case .none: break
        case .source: source = optional?.nilIfBlank
        case .area: area = optional?.nilIfBlank
        }

        let date = isoDate(now)
        let text = renderItemFile(title: cleanTitle, status: .open, priority: priority,
                                  date: date, source: source, area: area, body: body)
        let base = "\(date)-\(slugify(cleanTitle))"
        return try vault.createUniqueFile(inDirectory: config.directory, baseName: base, contents: text)
    }

    /// Flip a per-file item's frontmatter `status:` to done/dropped in place.
    static func resolve(_ resolution: ItemResolution, item: PerFileItem, vault: VaultAccess) throws {
        try vault.modifyTextFile(relativePath: item.relativePath) { text in
            try rewriteFrontmatterStatus(text: text, newStatusValue: resolution.status.frontmatterValue)
        }
    }

    // MARK: - Pure helpers (unit-tested directly)

    static func slugify(_ title: String, maxWords: Int = 8) -> String {
        let mapped = title.lowercased().map { ch -> Character in
            (("a"..."z").contains(ch) || ("0"..."9").contains(ch)) ? ch : " "
        }
        let words = String(mapped).split(separator: " ").prefix(maxWords)
        return words.joined(separator: "-")
    }

    static func renderItemFile(title: String, status: ItemStatus, priority: ItemPriority,
                               date: String, source: String?, area: String?, body: String) -> String {
        func yq(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var fm = ["---", "title: \(yq(title))", "status: \(status.frontmatterValue)",
                  "priority: \(priority.rawValue)", "date: \(date)"]
        if let source, !source.isEmpty { fm.append("source: \(yq(source))") }
        if let area, !area.isEmpty { fm.append("area: \(yq(area))") }
        fm.append("---")
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return fm.joined(separator: "\n") + "\n\n# \(title)\n\n" + trimmedBody + "\n"
    }

    /// Replace the value of the frontmatter `status:` line, preserving leading
    /// indentation and every other byte. Throws if there is no frontmatter or
    /// no status field.
    static func rewriteFrontmatterStatus(text: String, newStatusValue: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw WriteError.frontmatterNotFound
        }
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" { break }
            if let colon = lines[i].firstIndex(of: ":") {
                let key = lines[i][..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "status" {
                    let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
                    lines[i] = "\(leading)status: \(newStatusValue)"
                    return lines.joined(separator: "\n")
                }
            }
            i += 1
        }
        throw WriteError.statusFieldNotFound
    }

    // MARK: - Date

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run `xcodegen generate`, then the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemsWriterPureTests -only-testing:ScoutMobileTests/PerFileItemsWriterE2ETests`.
Expected: PASS — pure helpers + add/resolve e2e green.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Vault/PerFileItemsWriter.swift \
        ScoutMobileTests/PerFile/PerFileItemsWriterTests.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add PerFileItemsWriter (add + resolve, no git)"
```

---

### Task 7: PerFileItemsStore

**Files:**
- Create: `ScoutMobile/Services/PerFileItemsStore.swift`
- Test: `ScoutMobileTests/PerFile/PerFileItemsStoreTests.swift`

**Interfaces:**
- Consumes: `PerFileItem`, `PerFileItemParser` (Task 3), `PerFileTabConfig` (Task 4), `PerFileItemsWriter`, `ItemResolution` (Task 6), `VaultAccess` (existing).
- Produces: `@MainActor final class PerFileItemsStore: ObservableObject` with `init(vault:config:)`, `@Published private(set) var items: [PerFileItem]`, `@Published private(set) var state: State`, `let config: PerFileTabConfig`, `var activeCount: Int`, `func start()`, `func stop()`, `func reload() async`, `func addItem(title:priority:body:optional:) async throws`, `func resolve(_:item:) async throws`. `enum State: Equatable { case idle, loading, loaded, missing, failed(String) }`.

- [ ] **Step 1: Write the failing test**

Create `ScoutMobileTests/PerFile/PerFileItemsStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import ScoutMobile

@MainActor
@Suite("PerFileItemsStore")
struct PerFileItemsStoreTests {

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfile-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "perfile-store-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    private func write(_ contents: String, to rel: String, vault: VaultAccess) throws {
        // Ensure the subdirectory exists, then write.
        _ = try vault.createUniqueFile(inDirectory: (rel as NSString).deletingLastPathComponent,
                                       baseName: ((rel as NSString).lastPathComponent as NSString).deletingPathExtension,
                                       contents: contents)
    }

    @Test func missingDirectoryReportsMissing() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PerFileItemsStore(vault: vault, config: .wishlist)
        await store.reload()
        #expect(store.state == .missing)
        #expect(store.items.isEmpty)
    }

    @Test func loadsParsesAndCountsActive() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let open = """
        ---
        title: "Open one"
        status: open
        priority: high
        date: 2026-06-20
        ---

        # Open one

        Body.
        """
        let done = """
        ---
        title: "Done one"
        status: done
        priority: low
        date: 2026-06-19
        ---

        # Done one

        Body.
        """
        try write(open, to: "docs/wishlist/2026-06-20-open-one.md", vault: vault)
        try write(done, to: "docs/wishlist/2026-06-19-done-one.md", vault: vault)
        // A non-item file with no frontmatter must be skipped.
        try write("# Readme\n\nnot an item", to: "docs/wishlist/readme.md", vault: vault)

        let store = PerFileItemsStore(vault: vault, config: .wishlist)
        await store.reload()

        #expect(store.state == .loaded)
        #expect(store.items.count == 2)               // readme skipped
        #expect(store.activeCount == 1)               // only the open one
        // Newest-first by filename: 2026-06-20 before 2026-06-19.
        #expect(store.items.first?.title == "Open one")
    }

    @Test func addThenResolveUpdatesPublishedItems() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PerFileItemsStore(vault: vault, config: .wishlist)

        try await store.addItem(title: "New idea", priority: .high, body: "Notes.", optional: "Slack")
        #expect(store.items.count == 1)
        #expect(store.activeCount == 1)

        let item = try #require(store.items.first)
        try await store.resolve(.done, item: item)
        #expect(store.activeCount == 0)
        #expect(store.items.first?.status == .done)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemsStoreTests`.
Expected: FAIL — "Cannot find 'PerFileItemsStore' in scope".

- [ ] **Step 3: Create the store**

Create `ScoutMobile/Services/PerFileItemsStore.swift`:

```swift
import Foundation
import Combine

/// Loads + watches a per-file items directory (`docs/wishlist` or
/// `knowledge-base/research-queue`) and publishes the parsed items plus an
/// active-count for the tab badge.
///
/// iOS has no FSEvents on security-scoped external folders, so refresh is
/// polling-based: on `start()`, on foreground, on demand (pull-to-refresh),
/// and a 30 s timer — mirroring `ProposalsStore`. Each `*.md` file is one item;
/// files without frontmatter (index/readme files) parse to nil and are skipped.
@MainActor
final class PerFileItemsStore: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case missing          // the items directory does not exist (un-migrated vault)
        case failed(String)
    }

    @Published private(set) var items: [PerFileItem] = []
    @Published private(set) var state: State = .idle

    /// Number of items still active (open/in-progress) — feeds the tab badge.
    var activeCount: Int { items.filter(\.isActive).count }

    let config: PerFileTabConfig

    private let vault: VaultAccess
    private var refreshTimer: Timer?

    init(vault: VaultAccess, config: PerFileTabConfig) {
        self.vault = vault
        self.config = config
    }

    func start() {
        Task { await reload() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reload() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        if case .idle = state { state = .loading }
        let directory = config.directory
        let vault = self.vault
        let result: (state: State, items: [PerFileItem]) = await Task.detached {
            Self.load(directory: directory, vault: vault)
        }.value
        state = result.state
        // Avoid redundant publishes (the 30 s tick reparses every time).
        if result.items != items { items = result.items }
    }

    nonisolated private static func load(directory: String, vault: VaultAccess) -> (state: State, items: [PerFileItem]) {
        guard vault.fileExists(relativePath: directory) else { return (.missing, []) }
        let names: [String]
        do {
            names = try vault.listDirectory(relativePath: directory)
        } catch {
            return (.failed(error.localizedDescription), [])
        }
        let items = names
            .filter { $0.hasSuffix(".md") }
            // Newest-first: filenames are `YYYY-MM-DD-slug.md`, so reverse
            // lexicographic order is reverse-chronological.
            .sorted(by: >)
            .compactMap { name -> PerFileItem? in
                let rel = directory.isEmpty ? name : "\(directory)/\(name)"
                guard let data = vault.readFileIfExists(relativePath: rel),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                return PerFileItemParser.parseFile(contents: text, relativePath: rel)
            }
        return (.loaded, items)
    }

    // MARK: - Mutations

    func addItem(title: String, priority: ItemPriority, body: String, optional: String?) async throws {
        let config = self.config
        let vault = self.vault
        try await Task.detached {
            _ = try PerFileItemsWriter.addItem(config: config, title: title, priority: priority,
                                               body: body, optional: optional, vault: vault)
        }.value
        await reload()
    }

    func resolve(_ resolution: ItemResolution, item: PerFileItem) async throws {
        let vault = self.vault
        try await Task.detached {
            try PerFileItemsWriter.resolve(resolution, item: item, vault: vault)
        }.value
        await reload()
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run `xcodegen generate`, then the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemsStoreTests`.
Expected: PASS — missing/loaded/active-count and add→resolve tests green.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Services/PerFileItemsStore.swift \
        ScoutMobileTests/PerFile/PerFileItemsStoreTests.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add PerFileItemsStore (polling load + add/resolve)"
```

---

### Task 8: Status/priority pills + item card view

Presentational SwiftUI. No unit tests (the repo does not test views — cf. `ProposalStatusPill`, `ProposalCardView`); verified by build and, later, the run step.

**Files:**
- Create: `ScoutMobile/Views/Ideas/ItemStatusPill.swift`
- Create: `ScoutMobile/Views/Ideas/ItemPriorityPill.swift`
- Create: `ScoutMobile/Views/Ideas/PerFileItemCardView.swift`

**Interfaces:**
- Consumes: `ItemStatus`, `ItemPriority` (Task 1), `PerFileItem` (Task 3), `MarkdownBodyView` (Task 2), `ItemResolution` (Task 6).
- Produces: `struct ItemStatusPill: View { let status: ItemStatus }`, `struct ItemPriorityPill: View { let priority: ItemPriority }`, `struct PerFileItemCardView: View { let item: PerFileItem; let optionalLabel: String?; var onResolve: (@MainActor (ItemResolution) async throws -> Void)? }`.

- [ ] **Step 1: Create the status pill**

Create `ScoutMobile/Views/Ideas/ItemStatusPill.swift` (mirrors `ProposalStatusPill`, system colors):

```swift
import SwiftUI

/// Small color-coded capsule for a per-file item's lifecycle status.
struct ItemStatusPill: View {
    let status: ItemStatus

    var body: some View {
        Text(status.displayName.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
    }

    private var tint: Color {
        switch status {
        case .open:        return .blue
        case .inProgress:  return .orange
        case .done:        return .green
        case .dropped:     return .red
        case .unknown:     return .secondary
        }
    }
}
```

- [ ] **Step 2: Create the priority pill**

Create `ScoutMobile/Views/Ideas/ItemPriorityPill.swift`:

```swift
import SwiftUI

/// Small color-coded capsule for a per-file item's priority.
struct ItemPriorityPill: View {
    let priority: ItemPriority

    var body: some View {
        Text(priority.displayName.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
    }

    private var tint: Color {
        switch priority {
        case .urgent: return .red
        case .high:   return .orange
        case .medium: return .blue
        case .low:    return .secondary
        }
    }
}
```

- [ ] **Step 3: Create the card view**

Create `ScoutMobile/Views/Ideas/PerFileItemCardView.swift` (mirrors `ProposalCardView`):

```swift
import SwiftUI

/// One per-file Wishlist/Research item as a card: header (date + title +
/// priority/status pills), optional source/area line, markdown body, and —
/// for active items — Done / Drop actions. Owns its in-flight + error state so
/// a slow or failed write surfaces on the card itself.
struct PerFileItemCardView: View {
    let item: PerFileItem
    /// Display label for the optional source/area field (e.g. "Source", "Area").
    let optionalLabel: String?
    /// Performs the write. Throws so the card can show an inline error.
    /// `nil` for resolved (read-only) items.
    var onResolve: (@MainActor (ItemResolution) async throws -> Void)?

    @State private var inFlight: ItemResolution?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let label = optionalLabel, let value = optionalValue, !value.isEmpty {
                Text("\(label): \(value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.bodyBlocks.isEmpty {
                MarkdownBodyView(blocks: item.bodyBlocks)
            }
            if item.isActive, onResolve != nil {
                actions
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var optionalValue: String? { item.source ?? item.area }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !item.date.isEmpty {
                    Text(item.date)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ItemPriorityPill(priority: item.priority)
            ItemStatusPill(status: item.status)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actButton("Done", systemImage: "checkmark", resolution: .done, tint: .green)
            actButton("Drop", systemImage: "xmark", resolution: .dropped, tint: .secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actButton(
        _ label: String,
        systemImage: String,
        resolution: ItemResolution,
        tint: Color
    ) -> some View {
        let isBusy = inFlight == resolution
        Button {
            resolve(resolution)
        } label: {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(label)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(inFlight != nil)
    }

    private func resolve(_ resolution: ItemResolution) {
        guard let onResolve else { return }
        inFlight = resolution
        errorText = nil
        Task {
            do {
                try await onResolve(resolution)
            } catch {
                errorText = "Couldn't update the file — \(error.localizedDescription)"
            }
            inFlight = nil
        }
    }
}
```

- [ ] **Step 4: Regenerate and build**

Run `xcodegen generate`, then the build-only check.
Expected: `BUILD SUCCEEDED`, no errors.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Views/Ideas/ItemStatusPill.swift ScoutMobile/Views/Ideas/ItemPriorityPill.swift \
        ScoutMobile/Views/Ideas/PerFileItemCardView.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add item status/priority pills and card view"
```

---

### Task 9: Add-item sheet

Presentational form. Verified by build.

**Files:**
- Create: `ScoutMobile/Views/Ideas/AddItemSheet.swift`

**Interfaces:**
- Consumes: `PerFileTabConfig` (Task 4), `ItemPriority` (Task 1).
- Produces: `struct AddItemSheet: View { init(config:onSubmit:onCancel:) }` where `onSubmit: (String, ItemPriority, String, String?) async throws -> Void` (title, priority, body, optional source/area) and `onCancel: () -> Void`.

- [ ] **Step 1: Create the sheet**

Create `ScoutMobile/Views/Ideas/AddItemSheet.swift` (iOS-native Form sheet):

```swift
import SwiftUI

/// Modal sheet for adding a new per-file item (wishlist entry or research
/// topic). Title is required (Add disabled when blank); Priority is a segmented
/// picker from `config.priorities`; the optional Source/Area field appears only
/// when `config.optionalField.label != nil`. Submits via an async `onSubmit`
/// that throws so a failed write keeps the sheet open with an inline error.
struct AddItemSheet: View {
    let config: PerFileTabConfig
    let onSubmit: (String, ItemPriority, String, String?) async throws -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var priority: ItemPriority
    @State private var bodyText: String = ""
    @State private var optionalValue: String = ""
    @State private var submitting = false
    @State private var errorText: String?

    init(config: PerFileTabConfig,
         onSubmit: @escaping (String, ItemPriority, String, String?) async throws -> Void,
         onCancel: @escaping () -> Void) {
        self.config = config
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _priority = State(initialValue: config.defaultPriority)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !submitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("What should Scout do?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(config.priorities, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let label = config.optionalField.label {
                    Section(label) {
                        TextField(label, text: $optionalValue)
                    }
                }
                Section("Notes") {
                    TextField("Optional details", text: $bodyText, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add \(config.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Add") { submit() }.disabled(!canSubmit)
                    }
                }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        errorText = nil
        submitting = true
        let optional = optionalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await onSubmit(title, priority, bodyText, optional.isEmpty ? nil : optional)
                // Success: the presenter dismisses the sheet.
            } catch {
                errorText = error.localizedDescription
            }
            submitting = false
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run `xcodegen generate`, then the build-only check.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ScoutMobile/Views/Ideas/AddItemSheet.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add AddItemSheet form for new wishlist/research items"
```

---

### Task 10: PerFileListView (the Wishlist/Research pane)

**Files:**
- Create: `ScoutMobile/Views/Ideas/PerFileListView.swift`

**Interfaces:**
- Consumes: `PerFileItemsStore` (Task 7), `PerFileItemCardView` (Task 8), `AddItemSheet` (Task 9), `ItemResolution` (Task 6), `PerFileItem` (Task 3).
- Produces: `struct PerFileListView: View { @ObservedObject var store: PerFileItemsStore }` — a `List` pane with its own `+` toolbar item and add sheet, designed to be hosted inside `IdeasScreen`'s `NavigationStack`.

- [ ] **Step 1: Create the list view**

Create `ScoutMobile/Views/Ideas/PerFileListView.swift` (mirrors `ProposalsScreenContent`'s structure, no inner `NavigationStack`):

```swift
import SwiftUI

/// The Wishlist / Research pane: active items (priority-sorted) with Done/Drop,
/// a collapsible Resolved archive, and a ＋ toolbar button that presents
/// `AddItemSheet`. Hosted inside `IdeasScreen`'s shared `NavigationStack`, so it
/// carries no navigation chrome of its own beyond the toolbar ＋.
struct PerFileListView: View {
    @ObservedObject var store: PerFileItemsStore

    @State private var resolvedExpanded = false
    @State private var showingAdd = false

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add \(store.config.addNoun)")
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddItemSheet(
                config: store.config,
                onSubmit: { title, priority, body, optional in
                    try await store.addItem(title: title, priority: priority, body: body, optional: optional)
                    showingAdd = false
                },
                onCancel: { showingAdd = false }
            )
        }
        .task { await store.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        case .missing:
            unavailable(
                "No \(store.config.title.lowercased()) yet",
                icon: "tray",
                message: "Items appear here once a Scout run writes them. Tap ＋ to add one now."
            )
        case .failed(let err):
            unavailable("Couldn't load \(store.config.title.lowercased())",
                        icon: "exclamationmark.triangle", message: err)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let awaiting = store.items.filter(\.isActive).sorted { $0.priority < $1.priority }
        let resolved = store.items.filter { !$0.isActive }

        if store.items.isEmpty {
            unavailable(
                "Nothing here yet",
                icon: "sparkles",
                message: "Tap ＋ to add a \(store.config.addNoun)."
            )
        } else {
            Section {
                if awaiting.isEmpty {
                    Text("Nothing active right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(awaiting) { item in
                        PerFileItemCardView(item: item, optionalLabel: store.config.optionalField.label) { resolution in
                            try await store.resolve(resolution, item: item)
                        }
                    }
                }
            } header: {
                Text(activeHeader(count: awaiting.count))
            }

            if !resolved.isEmpty {
                Section {
                    Button {
                        withAnimation { resolvedExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("Resolved (\(resolved.count))")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: resolvedExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if resolvedExpanded {
                        ForEach(resolved) { item in
                            PerFileItemCardView(item: item, optionalLabel: store.config.optionalField.label, onResolve: nil)
                        }
                    }
                }
            }
        }
    }

    private func activeHeader(count: Int) -> String {
        switch count {
        case 0:  return "Active"
        case 1:  return "1 active"
        default: return "\(count) active"
        }
    }

    @ViewBuilder
    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run `xcodegen generate`, then the build-only check.
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ScoutMobile/Views/Ideas/PerFileListView.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): add PerFileListView pane (active/resolved + add)"
```

---

### Task 11: Extract `ProposalsList` from `ProposalsScreen`

The second half of "generalize proposals": pull the list body out into a `NavigationStack`-free pane so `IdeasScreen` can host it like `SessionsList`. `ProposalsScreen` keeps working after this (it wraps `ProposalsList` in its own stack), so the app stays green and unchanged until Task 13 swaps the tab.

**Files:**
- Modify: `ScoutMobile/Views/Proposals/ProposalsScreen.swift`

**Interfaces:**
- Produces: `struct ProposalsList: View { @ObservedObject var store: ProposalsStore }` — the `List` content (active/resolved + decide), `.refreshable`, no `NavigationStack`/`navigationTitle`.
- Preserves: `struct ProposalsScreen: View` (EnvironmentObject wrapper) renders `NavigationStack { ProposalsList(store:).navigationTitle("Proposals") }`.

- [ ] **Step 1: Confirm proposal tests are green (baseline)**

Run the test command scoped to `-only-testing:ScoutMobileTests/ProposalsParserTests`.
Expected: PASS.

- [ ] **Step 2: Refactor the file**

Replace the entire contents of `ScoutMobile/Views/Proposals/ProposalsScreen.swift` with:

```swift
import SwiftUI

/// The Proposals tab entry point: dreaming-generated SKILL.md change proposals
/// from `dreaming-proposals.md`. The list body lives in `ProposalsList` so the
/// "Ideas" container can host it as a pane alongside Wishlist and Research.
struct ProposalsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ProposalsList(store: model.proposals)
                .navigationTitle("Proposals")
        }
    }
}

/// The proposals list content — awaiting items with Approve/Decline and a
/// collapsible Resolved archive. No navigation chrome of its own; hosted inside
/// a parent `NavigationStack` (`ProposalsScreen` or `IdeasScreen`).
struct ProposalsList: View {
    @ObservedObject var store: ProposalsStore
    @State private var resolvedExpanded = false

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        case .missing:
            unavailable(
                "No proposals file",
                icon: "tray",
                message: "Dreaming runs write proposals to dreaming-proposals.md when they process feedback."
            )
        case .failed(let err):
            unavailable("Couldn't load proposals", icon: "exclamationmark.triangle", message: err)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let awaiting = store.proposals.filter(\.isAwaitingDecision)
        let resolved = store.proposals.filter { !$0.isAwaitingDecision }

        if store.proposals.isEmpty {
            unavailable(
                "No proposals",
                icon: "tray",
                message: "They'll appear here after a dreaming run files one."
            )
        } else {
            Section {
                if awaiting.isEmpty {
                    Text("Nothing awaiting your decision.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(awaiting) { proposal in
                        ProposalCardView(proposal: proposal) { decision in
                            try await store.decide(decision, proposal: proposal)
                        }
                    }
                }
            } header: {
                Text(awaitingHeader(count: awaiting.count))
            }

            if !resolved.isEmpty {
                Section {
                    Button {
                        withAnimation { resolvedExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("Resolved (\(resolved.count))")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: resolvedExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if resolvedExpanded {
                        ForEach(resolved) { proposal in
                            ProposalCardView(proposal: proposal, onDecide: nil)
                        }
                    }
                }
            }
        }
    }

    private func awaitingHeader(count: Int) -> String {
        switch count {
        case 0:  return "Awaiting your decision"
        case 1:  return "1 awaiting your decision"
        default: return "\(count) awaiting your decision"
        }
    }

    @ViewBuilder
    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
        }
    }
}
```

- [ ] **Step 3: Build and re-run proposal tests**

Run the build-only check, then the test command scoped to `-only-testing:ScoutMobileTests/ProposalsParserTests`.
Expected: `BUILD SUCCEEDED` and PASS — behavior preserved; `ProposalsScreen` still renders the same list.

- [ ] **Step 4: Commit**

```bash
git add ScoutMobile/Views/Proposals/ProposalsScreen.swift
git commit -m "refactor(proposals): extract ProposalsList pane for the Ideas container"
```

---

### Task 12: Wire the two stores into AppModel

**Files:**
- Modify: `ScoutMobile/App/AppModel.swift`

**Interfaces:**
- Consumes: `PerFileItemsStore` (Task 7), `PerFileTabConfig` (Task 4).
- Produces: `AppModel.wishlist: PerFileItemsStore`, `AppModel.research: PerFileItemsStore` (started/stopped alongside the existing stores).

- [ ] **Step 1: Add the stored properties**

In `ScoutMobile/App/AppModel.swift`, after `let proposals: ProposalsStore`, add:

```swift
    let wishlist: PerFileItemsStore
    let research: PerFileItemsStore
```

- [ ] **Step 2: Initialize them**

In `init()`, after `self.proposals = ProposalsStore(vault: vault)`, add:

```swift
        self.wishlist = PerFileItemsStore(vault: vault, config: .wishlist)
        self.research = PerFileItemsStore(vault: vault, config: .research)
```

- [ ] **Step 3: Start, stop, and foreground-refresh them**

In `clearVault()`, after `proposals.stop()`, add:

```swift
        wishlist.stop()
        research.stop()
```

In `startStores()`, in the `if !started { … }` branch after `proposals.start()`, add:

```swift
            wishlist.start()
            research.start()
```
and in the `else { … }` branch after `Task { await proposals.reloadIfChanged() }`, add:

```swift
            Task { await wishlist.reload() }
            Task { await research.reload() }
```

- [ ] **Step 4: Build**

Run the build-only check (no new files → `xcodegen generate` not required, but harmless).
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/App/AppModel.swift
git commit -m "feat(ideas): own wishlist and research stores in AppModel"
```

---

### Task 13: IdeasScreen container + tab swap + badge

**Files:**
- Create: `ScoutMobile/Views/Ideas/IdeasScreen.swift`
- Modify: `ScoutMobile/Views/RootView.swift`

**Interfaces:**
- Consumes: `AppModel.proposals/wishlist/research`, `ProposalsList` (Task 11), `PerFileListView` (Task 10).
- Produces: `struct IdeasScreen: View` — segmented `Picker` (Proposals/Wishlist/Research) hosting the three panes in one `NavigationStack`.
- Modifies: `RootView`'s `MainTabContent` to show the **Ideas** tab (lightbulb) with badge = `proposals.pendingCount + wishlist.activeCount + research.activeCount`.

- [ ] **Step 1: Create the container**

Create `ScoutMobile/Views/Ideas/IdeasScreen.swift` (mirrors `ActivityScreen`):

```swift
import SwiftUI

/// The merged Proposals + Wishlist + Research tab. A segmented control in the
/// navigation bar switches between dreaming proposals (Approve/Decline), the
/// per-file wishlist, and the research queue. Combining the three into one tab
/// keeps the tab bar at five slots — the same pattern `ActivityScreen` uses for
/// Sessions + Schedule. The Wishlist/Research panes contribute their own ＋ Add
/// toolbar button; the Proposals pane contributes none.
struct IdeasScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: Pane = .proposals

    enum Pane: String, CaseIterable {
        case proposals = "Proposals"
        case wishlist = "Wishlist"
        case research = "Research"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .proposals:
                    ProposalsList(store: model.proposals)
                case .wishlist:
                    PerFileListView(store: model.wishlist)
                case .research:
                    PerFileListView(store: model.research)
                }
            }
            .navigationTitle(pane.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { pane in
                            Text(pane.rawValue).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Swap the tab and badge in RootView**

Replace the entire contents of `ScoutMobile/Views/RootView.swift` with:

```swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.hasVault {
            MainTabView()
                .onAppear { model.startStores() }
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Observe the three Ideas stores directly so the tab badge updates live.
        MainTabContent(proposals: model.proposals, wishlist: model.wishlist, research: model.research)
    }
}

private struct MainTabContent: View {
    @ObservedObject var proposals: ProposalsStore
    @ObservedObject var wishlist: PerFileItemsStore
    @ObservedObject var research: PerFileItemsStore

    /// Everything across the Ideas tab still awaiting you: proposals needing a
    /// decision plus active (open/in-progress) wishlist and research items.
    private var ideasBadge: Int {
        proposals.pendingCount + wishlist.activeCount + research.activeCount
    }

    var body: some View {
        TabView {
            ActionItemsScreen()
                .tabItem { Label("Today", systemImage: "checklist") }
            ActivityScreen()
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            IdeasScreen()
                .tabItem { Label("Ideas", systemImage: "lightbulb") }
                .badge(ideasBadge)
            KnowledgeScreen()
                .tabItem { Label("Knowledge", systemImage: "books.vertical") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
```

- [ ] **Step 3: Regenerate, build, and run the full unit suite**

Run `xcodegen generate`, then the build-only check, then the full test command (all of `ScoutMobileTests`).
Expected: `BUILD SUCCEEDED` and every suite passes (existing + new).

- [ ] **Step 4: Launch in the simulator and verify the UI**

Run the app against a vault to confirm the three-pane container, segmented control, badge, and the ＋ Add button on Wishlist/Research only. Use the `/run` skill if available, or:
```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
xcodebuild build -project ScoutMobile.xcodeproj -scheme ScoutMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
# Install/launch the built .app (path from the build output's CODESIGNING/Products dir),
# or open the scheme from Xcode for an interactive run.
```
Expected (manual): the **Ideas** tab shows a `Proposals | Wishlist | Research` segmented control; Proposals behaves exactly as before; Wishlist/Research show the friendly "No … yet" empty state on this un-migrated vault, with a working ＋ that opens the Add sheet. Adding an item creates `docs/wishlist/<date>-<slug>.md` and the item appears.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobile/Views/Ideas/IdeasScreen.swift ScoutMobile/Views/RootView.swift ScoutMobile.xcodeproj
git commit -m "feat(ideas): merge Proposals/Wishlist/Research into one Ideas tab"
```

---

### Task 14: Realistic fixture + full verification

Adds the per-file contract example the spec calls for (a real `.md` loaded via `Bundle`, the pattern `SessionLogParserTests` uses), and does the final whole-suite + build pass.

**Files:**
- Create: `ScoutMobileTests/Fixtures/wishlist-item-example.md`
- Create: `ScoutMobileTests/PerFile/PerFileItemFixtureTests.swift`

**Interfaces:**
- Consumes: `PerFileItemParser` (Task 3); `Bundle(for:)` resource loading (existing test pattern).

- [ ] **Step 1: Add the fixture file**

Create `ScoutMobileTests/Fixtures/wishlist-item-example.md` (a real per-file item exactly as the plugin/desktop write it):

```markdown
---
title: "Surface add-write failures in the Add sheet"
status: open
priority: high
date: 2026-06-19
source: "Scout#40 review follow-up"
---

# Surface add-write failures in the Add sheet

The add path currently swallows write errors. Show them inline on the sheet,
the way the resolve path already surfaces errors on the card.

```swift
try await store.addItem(title: title, priority: priority, body: body, optional: optional)
```
```

- [ ] **Step 2: Write the failing contract test**

Create `ScoutMobileTests/PerFile/PerFileItemFixtureTests.swift`:

```swift
import Testing
import Foundation
@testable import ScoutMobile

@Suite("PerFileItem fixture contract")
struct PerFileItemFixtureTests {

    @Test func parsesTheRealWishlistFixture() throws {
        let url = try #require(Bundle(for: PerFileFixtureToken.self)
            .url(forResource: "wishlist-item-example", withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let item = try #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "docs/wishlist/wishlist-item-example.md"))

        #expect(item.title == "Surface add-write failures in the Add sheet")
        #expect(item.status == .open)
        #expect(item.priority == .high)
        #expect(item.date == "2026-06-19")
        #expect(item.source == "Scout#40 review follow-up")
        #expect(item.isActive)
        // The `# Heading` is stripped; the fenced code block is lifted out verbatim.
        #expect(!item.bodyMarkdown.hasPrefix("# "))
        let code = item.bodyBlocks.compactMap { block -> String? in
            if case .code(_, let c) = block { return c } else { return nil }
        }
        #expect(code.first?.contains("store.addItem(") == true)
    }
}

private final class PerFileFixtureToken {}
```

- [ ] **Step 3: Run the test to verify it fails**

Run `xcodegen generate`, then the test command scoped to `-only-testing:ScoutMobileTests/PerFileItemFixtureTests`.
Expected: FAIL first if the resource is not yet bundled (nil URL) — then PASS once `xcodegen generate` has folded the new `Fixtures/*.md` into the test target's resources build phase. (Re-run after `xcodegen generate` if the first run predated it.)

- [ ] **Step 4: Full verification — whole suite + app build**

Run the full test command (all `ScoutMobileTests`) and the build-only check.
Expected: every suite passes; `BUILD SUCCEEDED`. Capture the `Suite … passed` / test counts in the commit body if helpful.

- [ ] **Step 5: Commit**

```bash
git add ScoutMobileTests/Fixtures/wishlist-item-example.md \
        ScoutMobileTests/PerFile/PerFileItemFixtureTests.swift ScoutMobile.xcodeproj
git commit -m "test(ideas): add per-file item fixture contract test"
```

---

## Final state

After Task 14: a five-tab app (Today · Activity · **Ideas** · Knowledge · Settings) where Ideas hosts Proposals (unchanged), Wishlist, and Research behind a segmented control; add + resolve work for the per-file panes; the tab badge sums everything awaiting you; and the per-file contract is locked by tests. On this un-migrated vault the Wishlist/Research panes show their empty state until Scout is updated to write the per-file directories.

Open the branch as a PR per the team's process (e.g. the `create-pr` skill) once the user is ready.
