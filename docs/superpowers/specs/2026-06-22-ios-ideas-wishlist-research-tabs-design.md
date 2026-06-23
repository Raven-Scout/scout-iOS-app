# iOS "Ideas" tab — Proposals + Wishlist + Research

- **Date:** 2026-06-22
- **Status:** Approved (design)
- **Ports:** [Raven-Scout/Scout#40](https://github.com/Raven-Scout/Scout/pull/40) — "Scout.app Wishlist & Research tabs (per-file core)"

## Context

Desktop Scout.app PR #40 added two sidebar tabs, **Wishlist** and **Research**, backed by
a generalized `PerFileItems/` module: each item is its own `.md` file with YAML frontmatter
(`docs/wishlist/*.md`, `knowledge-base/research-queue/*.md`). It supports view + add + resolve,
and is a config-parameterized near-copy of Proposals (Proposals itself was left untouched).

This brings the same two features to Scout-iOS, but **merged with the existing Proposals tab
into a single section** with a segmented control — mirroring how `ActivityScreen` already merges
Sessions and Schedule into one tab. The combined tab is named **Ideas**.

## Decisions

1. **Data format: per-file, matching desktop.** iOS reads `docs/wishlist/*.md` and
   `knowledge-base/research-queue/*.md` with YAML frontmatter — byte-for-byte the same contract
   as the desktop module and the scout-plugin schema.
2. **Write scope: view + add + resolve** (full desktop parity). Add a new item from the phone;
   mark items Done/Dropped.
3. **Tab name: "Ideas"** (lightbulb icon). The tab hosts a `Proposals | Wishlist | Research`
   segmented control; the precise pane names live on the control.
4. **Badge: sum of all three active counts** — `proposals.pendingCount + wishlist.activeCount +
   research.activeCount`, updated live.
5. **"Make proposals more general":** a small, conservative refactor extracts two shared pieces
   from Proposals (body rendering + list content); Proposals' parser/status/writer stay untouched.
6. **Omitted (YAGNI):** desktop's Settings path-overrides (`wishlistPath`/`researchQueuePath`)
   and git commits. iOS hardcodes the default vault-relative directories and writes plain files
   (iCloud/Obsidian sync handles propagation — iOS has no git, per `CLAUDE.md`).

### Known consequence

This vault still uses the **old single-file format** (`docs/Wishlist.md` +
`Wishlist-in-progress.md` + `Wishlist-done.md`; `knowledge-base/research-queue.md`). The new
per-file directories do not exist here yet. So on this vault the Wishlist/Research panes show a
friendly empty state until the vault is migrated (by updating + running Scout, which writes the
per-file files). This is the accepted trade-off of decision 1 and the "#38 empty-tab" lesson
applied deliberately rather than by accident.

## Data contract (per-file item)

Each `*.md` file in the items directory is one item:

```markdown
---
title: "Some title"
status: open            # open | in-progress | done | dropped
priority: medium        # urgent | high | medium | low
date: 2026-06-22
source: "Slack thread"  # wishlist only, optional
area: "Auth"            # research only, optional
---

# Some title

Free-form markdown body…
```

- **Status:** `open` / `in-progress` are *active* (shown under "Awaiting"); `done` / `dropped`
  (and any unrecognized value) are *resolved*.
- **Priority:** `urgent / high / medium / low`, urgent-first sort. Missing/unrecognized → `medium`.
- **Parsing:** frontmatter is the leading `---`-fenced block. `date`/`title` fall back to the
  filename (`YYYY-MM-DD` prefix and stem). The leading `# Heading` is stripped from the rendered
  body. A file with **no frontmatter parses to nil** (skips index/non-item files).
- **File naming on add:** `YYYY-MM-DD-slug.md`, collision-suffixed (`-2`, `-3`, …).

## Architecture

Respects the iOS repo's existing layering (`Models → Parsing → Services/Vault → Views`), not the
desktop's feature-folder. Wishlist and Research are two `PerFileTabConfig` **values**, not types.

### New files

| Layer | File | Notes |
|---|---|---|
| Models | `Models/ItemStatus.swift` | ported; `open/inProgress/done/dropped/unknown` |
| Models | `Models/ItemPriority.swift` | ported; `urgent/high/medium/low`, `Comparable` |
| Models | `Models/PerFileItem.swift` | identity = **vault-relative path** (iOS adaptation of desktop's `fileURL`) |
| Models | `Models/PerFileTabConfig.swift` | `title`, `priorities`, `defaultPriority`, `optionalField` (Source/Area), `addNoun`, vault-relative `directory`. No `pathOverrideKey`/git. |
| Parsing | `Parsing/PerFileItemParser.swift` | ported byte-for-byte (frontmatter split + fields + body cleanup) |
| Services | `Services/PerFileItemsStore.swift` | iOS-native polling store (see below) |
| Vault | `Vault/PerFileItemsWriter.swift` | add + resolve, no git |
| Views | `Views/Ideas/IdeasScreen.swift` | container; segmented `Picker`, hosts the three panes |
| Views | `Views/Ideas/PerFileListView.swift` | active/resolved split, collapsible Resolved, +Add |
| Views | `Views/Ideas/PerFileItemCardView.swift` | card with pills + Done/Drop |
| Views | `Views/Ideas/ItemStatusPill.swift` | restyled to iOS (cf. `ProposalStatusPill`) |
| Views | `Views/Ideas/ItemPriorityPill.swift` | restyled to iOS |
| Views | `Views/Ideas/AddItemSheet.swift` | iOS sheet (Title/Priority/Source-or-Area/Notes) |
| Views | `Views/Components/MarkdownBodyView.swift` | extracted shared body renderer (see refactor) |

### Modified files (the "more general" refactor — only these touch existing code)

- `Models/Proposal.swift` — extract `ProposalBodyBlock` enum out to a shared
  `Models/MarkdownBodyBlock.swift` (pure rename/move); update references.
- `Views/Proposals/ProposalBodyView.swift` → `Views/Components/MarkdownBodyView.swift`
  (rename/move); used by Proposals + per-file cards.
- `Views/Proposals/ProposalsScreen.swift` — extract the list body into a `ProposalsList` view
  with **no inner `NavigationStack`**, so the container can host it as a pane (mirrors
  `SessionsList`/`ScheduleList`). `ProposalsScreen` itself is removed from the tab bar.
- `Vault/VaultAccess.swift` — add one method to create a uniquely-named file in a (possibly
  absent) subdirectory, inside the security scope.
- `App/AppModel.swift` — own two `PerFileItemsStore`s + one `PerFileItemsWriter`; start/stop them.
- `Views/RootView.swift` — replace the `ProposalsScreen` tab with the **Ideas** tab; badge =
  sum of the three active counts (observe all three stores).

### Component detail

**`PerFileItemsStore` (`@MainActor ObservableObject`).** Polling, modeled on `ProposalsStore`
(iOS has no FSEvents on security-scoped folders). Publishes `items`, `activeCount`, and a
`State` (`idle/loading/loaded/missing/failed`). On reload: `VaultAccess.listDirectory(config.directory)`
→ read+parse each `*.md` → sort newest-first by filename. A missing directory → `.missing`
(friendly empty state). Cheap `reloadIfChanged` via a directory signature (sorted
filename+size list) so the 30 s timer doesn't reparse unnecessarily. Two instances
(wishlist, research). Refresh triggers: `start()` timer, foreground, pull-to-refresh, and an
explicit `reload()` after each write.

**`PerFileItemsWriter`.** Pure helpers ported from desktop (`slugify`, `renderItemFile`,
`uniqueURL`, `rewriteFrontmatterStatus`) — unit-tested directly.
- *Resolve:* `VaultAccess.modifyTextFile(relativePath:)` flips the frontmatter `status:` line in
  place (coordinated read-modify-write) — same surface as `ProposalsWriter.decide`.
- *Add:* render frontmatter+body, then the new `VaultAccess` create-file method writes
  `YYYY-MM-DD-slug.md` into the config directory, creating the directory if needed and
  collision-suffixing the name. No git commit.

**`VaultAccess` new method** (sketch): `createUniqueFile(inDirectoryRelativePath:baseName:ext:contents:) -> String`
— within `withVault`, ensure the directory exists (`FileManager.createDirectory`
`withIntermediateDirectories: true`), pick a non-colliding `baseName(.ext|-2.ext|…)`, write via
`NSFileCoordinator` (`.forReplacing`, atomic), and return the new vault-relative path. Uniqueness
check and write happen inside the same security scope.

**`IdeasScreen`** (container, modeled on `ActivityScreen`): a single `NavigationStack`; a principal
segmented `Picker` over `Pane { proposals, wishlist, research }` (default `.proposals`); the body
switches between `ProposalsList`, `PerFileListView(config: .wishlist)`, and
`PerFileListView(config: .research)`. A trailing **+** toolbar item appears only for the wishlist
/research panes and presents `AddItemSheet` for the active config.

**`PerFileTabConfig` values:**
- `.wishlist` — title "Wishlist", priorities `[high, medium, low]` (default `medium`), optional
  `Source`, directory `docs/wishlist`, addNoun "wishlist item".
- `.research` — title "Research", priorities `[urgent, high, medium, low]` (default `medium`),
  optional `Area`, directory `knowledge-base/research-queue`, addNoun "research topic".

## Data flow

- **Read:** store lists the directory → reads/parses each file → publishes `items`. Panes derive
  active vs. resolved and sort. Tab badge sums the three active/pending counts reactively.
- **Add:** `AddItemSheet` → `PerFileItemsWriter.addItem` → new file written → `store.reload()`.
- **Resolve:** card Done/Drop → `PerFileItemsWriter.resolve` flips `status:` → `store.reload()`.

## Error handling

- Directory missing → `.missing` state, friendly empty copy (covers the un-migrated vault).
- Read/parse failure of one file → that file is skipped (`compactMap`); others still load.
- Add/resolve failures surface inline (the sheet for add; on the card for resolve), matching the
  desktop follow-up and Proposals' existing card-error pattern.
- Non-UTF-8 / unreadable directory → `.failed(message)`.

## Testing (Swift Testing, per `CLAUDE.md`)

Port desktop's pure tests and add iOS-specific ones:
- `PerFileItemParser` — frontmatter split, field parse, status/priority parse, date-prefix
  fallback, leading-heading strip, no-frontmatter → nil.
- `ItemStatus` / `ItemPriority` — parse, `isActive`, ordering, display/frontmatter values.
- `PerFileItemsWriter` pure helpers — `slugify`, `renderItemFile`, `uniqueURL`,
  `rewriteFrontmatterStatus`.
- Writer e2e — add then resolve against a temp directory (via a `VaultAccess` pointed at a temp
  path), asserting file creation, collision suffixing, and the status flip.
- **Fixture:** add a real per-file item `.md` under `ScoutMobileTests/Fixtures/` (the contract
  this vault lacks today) rather than inlining strings.

Run with the project's known-good incantation (`DEVELOPER_DIR` exported, iPhone 17 Pro / iOS 26.5,
`-only-testing:ScoutMobileTests`, `CODE_SIGNING_ALLOWED=NO`). Run `xcodegen generate` after adding
files (XcodeGen globs by folder; never hand-edit the `.xcodeproj`).

## Out of scope

- Migrating the vault's old single-file Wishlist/Research data to per-file (that is plugin-side).
- Settings path-overrides and git commits (decision 6).
- Editing item title/priority/body after creation, or in-progress state transitions — sessions
  still own those (matches desktop's view+add+resolve scope).
