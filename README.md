# Scout for iOS

An iPhone companion app for the [Scout](https://github.com/Raven-Scout/scout-plugin) Claude Code plugin — the iOS sibling of the [Scout macOS app](https://github.com/Raven-Scout/Scout).

Scout runs as scheduled Claude Code sessions on your Mac and writes everything into a vault folder (markdown + logs). When that vault lives inside your Obsidian iCloud folder, this app reads it on your iPhone:

- **Today** — the daily action-items briefing rendered natively: sections (🔴 Urgent / 🟡 To Do / 🟢 Watching / 💡 Focus / 📅 Meetings), task cards with stable `[#TAG]` ids, comments, snooze/carry-forward markers, meeting tables, and search + status filters. Mark tasks done, snooze them, or add comments — edits are written straight back into the markdown and sync to your Mac via iCloud.
- **Sessions** — run history parsed from `.scout-logs/`: status (success / failed / timeout / rate-limited / skipped / orphaned), duration, cost from `usage-tracker.jsonl`, detected error patterns, and the full log.
- **Schedule** — a read-only view of `.scout-state/schedule.yaml` with locally computed upcoming fires.
- **Knowledge** — browse the vault's markdown (knowledge base, people, projects) with tappable `[[wikilinks]]`.
- **Notifications** — background refresh checks for newly finished runs and fires a local notification (optionally failures only).
- **Deep links** — Linear issue refs, GitHub PR URLs, and Slack thread URLs in action items open in their native apps.

## Requirements

- iOS 17+, Xcode 16+ (built against Xcode 26).
- A Scout vault reachable from the iPhone — in practice: the vault folder inside `iCloud Drive/Obsidian/`.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project (`brew install xcodegen`).

## Build & run

```bash
xcodegen generate
open ScoutMobile.xcodeproj
```

Select your development team on the ScoutMobile target, then Product → Run onto your iPhone.

First launch shows a folder picker — navigate to iCloud Drive → Obsidian → your Scout folder and select it. The app stores a security-scoped bookmark, so the grant survives restarts.

### Tests

```bash
xcodebuild test -project ScoutMobile.xcodeproj -scheme ScoutMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`ScoutMobileTests` includes the cross-platform parser contract corpus (`parser-corpus.json`) shared byte-for-byte with the desktop app and the Python plugin — the line-level action-items parser must agree across all three.

The UI smoke test walks every tab against a sample vault. Point it at one with:

```bash
TEST_RUNNER_SCOUT_VAULT_PATH=/path/to/vault xcodebuild test … -only-testing:ScoutMobileUITests
```

(Debug builds also honor a `SCOUT_VAULT_PATH` env var to skip the folder picker — useful in the simulator.)

## How it works

| Desktop app | iOS app |
| --- | --- |
| FSEvents file watching | polling (foreground timer + pull-to-refresh) + BGAppRefreshTask in background |
| `scoutctl` CLI for mutations | direct line-targeted markdown edits via `NSFileCoordinator` (mark done, snooze, comment) |
| `scoutctl schedule list-upcoming` | local YAML-subset parser + upcoming-fire calculator |
| `~/Scout/` fixed path | user-picked folder, security-scoped bookmark |
| git integration (commits per run) | omitted (no git on iOS) |
| schedule editing | read-only (atomic header-preserving rewrites stay scoutctl's job) |

Mutations re-locate the task line by its stable `[#TAG]` prefix (with subject-match fallback for legacy lines) rather than trusting parse-time line numbers, so edits stay correct when Scout rewrites the file between parses. Reads trigger iCloud downloads for undownloaded placeholders and wait for materialization.

## Repo layout

```
project.yml            # XcodeGen manifest (project is generated, not committed)
ScoutMobile/
  App/                 # entry point, AppModel, settings
  Models/              # ActionTask, Run, Slot, UsageEntry, …
  Parsing/             # action-items parser (contract), session-log + schedule parsers
  Vault/               # bookmark + coordinated file access, markdown writer
  Services/            # stores, notifications, background refresh, link opener
  Views/               # SwiftUI screens per tab
ScoutMobileTests/      # unit tests + shared fixtures (parser corpus, real logs)
ScoutMobileUITests/    # tab-walk smoke test with screenshots
```

## License & legal

This app is open-source under the [MIT License](LICENSE).

Scout is local-first and collects no data of its own — the iOS app reads and writes a vault folder you choose (typically inside your own iCloud Drive / Obsidian), and sync happens between your own devices via your iCloud. See the project's shared legal documents:

- **Privacy Policy** — https://raven-scout.github.io/scout-plugin/privacy.html
- **Terms of Use** — https://raven-scout.github.io/scout-plugin/terms.html
- **[Security Policy](https://github.com/Raven-Scout/.github/blob/main/SECURITY.md)** · **[Code of Conduct](https://github.com/Raven-Scout/.github/blob/main/CODE_OF_CONDUCT.md)**

Scout is an independent project, not affiliated with Anthropic, Microsoft, Keboola, or any other company.
