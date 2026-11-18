import Testing
import Foundation
@testable import ScoutMobile

struct SessionLogParserTests {

    func fixtureText(_ name: String) throws -> String {
        let url = try #require(Bundle(for: FixtureToken.self).url(forResource: name, withExtension: "log"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesFilenames() throws {
        let tz = TimeZone(identifier: "Europe/Prague")!
        let parsed = try #require(SessionLogParser.parseFilename(
            URL(fileURLWithPath: ".scout-logs/scout-2026-06-12_08-38.log"),
            timeZone: tz
        ))
        #expect(parsed.runnerScript == "run-scout.sh")
        #expect(parsed.type == .morningBriefing)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        #expect(cal.component(.hour, from: parsed.startedAt) == 8)
        #expect(cal.component(.minute, from: parsed.startedAt) == 38)

        let dreaming = try #require(SessionLogParser.parseFilename(
            URL(fileURLWithPath: "dreaming-2026-04-19_07-00.log"), timeZone: tz
        ))
        #expect(dreaming.type == .dreaming)

        #expect(SessionLogParser.parseFilename(URL(fileURLWithPath: "usage-tracker.jsonl")) == nil)
        #expect(SessionLogParser.parseFilename(URL(fileURLWithPath: "random.log")) == nil)
    }

    @Test func parsesFinishMarkerWithCEST() {
        let body = SessionLogParser.parseBody(
            text: """
            some output
            === Scout run finished at Fri Jun 12 13:17:49 CEST 2026 (exit code: 1, duration: 417s) ===
            """,
            sizeBytes: 100
        )
        #expect(body.exitCode == 1)
        #expect(body.status == .failure)
        #expect(body.durationSeconds == 417)
        let ended = body.endedAt
        #expect(ended != nil)
        if let ended {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Prague")!
            #expect(cal.component(.hour, from: ended) == 13)
            #expect(cal.component(.minute, from: ended) == 17)
        }
    }

    @Test func parsesSuccessAndStatusOrdering() {
        let success = SessionLogParser.parseBody(
            text: "=== Scout run finished at Sun Apr 19 15:00:01 EDT 2026 (exit code: 0, duration: 120s) ===",
            sizeBytes: 10
        )
        #expect(success.status == .success)

        let timeout = SessionLogParser.parseBody(
            text: "=== TIMEOUT: killed\n=== Scout run finished at Sun Apr 19 15:00:01 EDT 2026 (exit code: 124) ===",
            sizeBytes: 10
        )
        #expect(timeout.status == .timeout)

        let rateLimited = SessionLogParser.parseBody(
            text: "Rate limit detected: backing off\n=== Scout run finished at Sun Apr 19 15:00:01 EDT 2026 (exit code: 0) ===",
            sizeBytes: 10
        )
        #expect(rateLimited.status == .rateLimited)

        let running = SessionLogParser.parseBody(text: "still going…", sizeBytes: 10)
        #expect(running.status == .running)
    }

    @Test func parsesRealLogFixtures() throws {
        // This fixture is a concurrency-skip log ("Another SCOUT session
        // running") with no finish marker.
        let text = try fixtureText("scout-2026-04-19_08-08")
        let body = SessionLogParser.parseBody(text: text, sizeBytes: Int64(text.utf8.count))
        #expect(body.status == .skippedConcurrency)

        let dreaming = try fixtureText("dreaming-2026-04-19_07-00")
        let dreamingBody = SessionLogParser.parseBody(text: dreaming, sizeBytes: Int64(dreaming.utf8.count))
        #expect(dreamingBody.status.isTerminal || dreamingBody.status == .running)
    }

    @Test func orphanPromotion() {
        let started = Date(timeIntervalSinceNow: -3 * 3600)
        let promoted = SessionLogParser.promoteOrphan(
            parsedStatus: .running, startedAt: started, type: .morningBriefing, now: Date()
        )
        #expect(promoted == .orphaned)

        let fresh = SessionLogParser.promoteOrphan(
            parsedStatus: .running, startedAt: Date(), type: .morningBriefing, now: Date()
        )
        #expect(fresh == .running)
    }

    @Test func staleRunningResolution() {
        func makeRun(_ type: RunType, startedAt: Date, status: RunStatus) -> Run {
            Run(
                id: Run.makeId(type: type, startedAt: startedAt),
                type: type, runnerScript: "run-scout.sh",
                startedAt: startedAt, endedAt: nil, status: status,
                exitCode: nil, durationSeconds: nil, cost: nil, budgetCap: nil,
                logPath: URL(fileURLWithPath: "/tmp/x.log"), logSizeBytes: 0,
                errorsDetected: []
            )
        }
        let old = makeRun(.dreaming, startedAt: Date(timeIntervalSinceNow: -7200), status: .running)
        let newer = makeRun(.dreaming, startedAt: Date(timeIntervalSinceNow: -600), status: .success)
        let resolved = SessionLogParser.resolveStaleRunning([newer, old])
        #expect(resolved.first { $0.id == old.id }?.status == .orphaned)
        #expect(resolved.first { $0.id == newer.id }?.status == .success)
    }
}

/// Unique run log names (Raven-Scout/Scout#673): a run claims the minute name
/// `<runner>-YYYY-MM-DD_HH-MM.log` and falls back to
/// `<runner>-YYYY-MM-DD_HH-MM-SS-PID.log` only when another run already took
/// that minute. Mirrors the desktop app's SessionLogServiceTests.
struct UniqueRunLogNameTests {

    static let ny = TimeZone(identifier: "America/New_York")!

    static func parse(_ name: String) -> SessionLogParser.ParsedFilename? {
        SessionLogParser.parseFilename(URL(fileURLWithPath: ".scout-logs/\(name).log"), timeZone: ny)
    }

    static func makeRun(_ type: RunType, startedAt: Date, status: RunStatus, pid: Int? = nil, log: String = "/tmp/x.log") -> Run {
        Run(
            id: Run.makeId(type: type, startedAt: startedAt, pid: pid),
            type: type, runnerScript: "run-scout.sh",
            startedAt: startedAt, endedAt: nil, status: status,
            exitCode: nil, durationSeconds: nil, cost: nil, budgetCap: nil,
            logPath: URL(fileURLWithPath: log), logSizeBytes: 0,
            errorsDetected: []
        )
    }

    // MARK: - Both name forms and the id rule

    @Test func minuteNameKeepsItsIdentity() throws {
        let parsed = try #require(Self.parse("scout-2026-04-20_08-03"))
        #expect(parsed.pid == nil)
        #expect(parsed.type == .morningBriefing)
        #expect(Calendar(identifier: .gregorian).dateComponents(in: Self.ny, from: parsed.startedAt).second == 0)
        // The id every older client and the notified-run set already know.
        #expect(Run.makeId(type: parsed.type, startedAt: parsed.startedAt, pid: parsed.pid)
                == "morningBriefing-2026-04-20T12:03:00Z")
        #expect(Run.makeId(type: parsed.type, startedAt: parsed.startedAt)
                == Run.makeId(type: parsed.type, startedAt: parsed.startedAt, pid: nil))
    }

    @Test func secondsAndPidName() throws {
        let parsed = try #require(Self.parse("dreaming-2026-04-18_22-00-31-4242"))
        #expect(parsed.runnerScript == "run-dreaming.sh")
        #expect(parsed.type == .dreaming)
        #expect(parsed.pid == 4242)
        let comps = Calendar(identifier: .gregorian).dateComponents(in: Self.ny, from: parsed.startedAt)
        #expect([comps.hour, comps.minute, comps.second] == [22, 0, 31])
        #expect(Run.makeId(type: parsed.type, startedAt: parsed.startedAt, pid: parsed.pid)
                == "dreaming-2026-04-19T02:00:31Z-4242")
    }

    @Test func rejectsMalformedUniqueNames() {
        for name in ["scout-2026-04-20_08-03-25", "scout-2026-04-20_08-03-5-4242", "scout-2026-04-20_08-03-25-0",
                     "scout-2026-04-20_08-03-61-4242", "scout-2026-04-20_08-03-25-42a", "scout-2026-04-20_08-03-25-4242-1",
                     "scout-2026-04-20_08-xx", "scout-2026-04-20_08--03"] {
            #expect(Self.parse(name) == nil, "\(name)")
        }
    }

    @Test func sameMinuteRunsGetDistinctIds() throws {
        let names = ["scout-2026-04-20_08-03", "scout-2026-04-20_08-03-31-4242", "scout-2026-04-20_08-03-31-4243"]
        let ids = try names.map { name in
            let p = try #require(Self.parse(name))
            return Run.makeId(type: p.type, startedAt: p.startedAt, pid: p.pid)
        }
        #expect(Set(ids).count == 3)
    }

    // MARK: - Sort order

    @Test func sortsNewestFirstByMinuteSecondPid() throws {
        let names = [
            "scout-2026-04-20_08-03-31-4243",
            "scout-2026-04-20_08-04",
            "scout-2026-04-20_08-03",
            "scout-2026-04-20_08-03-31-4242",
            "scout-2026-04-20_08-03-00-17",
            "scout-2026-04-20_08-03-45-12",
        ]
        let entries = try names.map { name -> (run: Run, pid: Int?) in
            let p = try #require(Self.parse(name))
            return (Self.makeRun(p.type, startedAt: p.startedAt, status: .success, pid: p.pid, log: "/x/\(name).log"), p.pid)
        }
        let order = SessionLogParser.newestFirst(entries).map { $0.logPath.deletingPathExtension().lastPathComponent }
        #expect(order == [
            "scout-2026-04-20_08-04",
            "scout-2026-04-20_08-03-45-12",
            "scout-2026-04-20_08-03-31-4243",
            "scout-2026-04-20_08-03-31-4242",
            "scout-2026-04-20_08-03-00-17",
            "scout-2026-04-20_08-03",
        ])
    }

    // MARK: - Lock skips don't orphan the live run

    /// The runner skips on the session lock before it holds it: a lock skip
    /// is evidence that the earlier run is alive, so it orphans nothing.
    @Test func aLaterLockSkipDoesNotOrphan() {
        let now = Date()
        let live = Self.makeRun(.consolidation, startedAt: now.addingTimeInterval(-600), status: .running)
        let skipped = Self.makeRun(.consolidation, startedAt: now.addingTimeInterval(-300), status: .skippedConcurrency)
        let out = SessionLogParser.resolveStaleRunning([skipped, live])
        #expect(out.first { $0.id == live.id }?.status == .running)
        #expect(out.first { $0.id == skipped.id }?.status == .skippedConcurrency)
    }

    /// A budget skip happens after the runner took the lock, and so does a
    /// finished run: either shows the earlier run no longer holds it.
    @Test(arguments: [RunStatus.success, .failure, .timeout, .skippedBudget])
    func aLaterRunPastTheLockStillOrphans(_ status: RunStatus) {
        let now = Date()
        let stuck = Self.makeRun(.consolidation, startedAt: now.addingTimeInterval(-600), status: .running)
        let later = Self.makeRun(.consolidation, startedAt: now.addingTimeInterval(-300), status: status)
        let out = SessionLogParser.resolveStaleRunning([later, stuck])
        #expect(out.first { $0.id == stuck.id }?.status == .orphaned)
    }

    // MARK: - SessionsStore keeps fallback-named runs

    /// The bug this guards: a run skipped by the session lock in the live
    /// run's minute used to append its skip line to the live run's log. Now
    /// it has its own seconds+PID log, which the store must keep as its own run.
    @Test func storeKeepsASameMinuteSkipAsItsOwnRun() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scout-test-\(UUID().uuidString)", isDirectory: true)
        let logs = dir.appendingPathComponent(SessionsStore.logsDir, isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        let vault = VaultAccess(defaults: defaults)

        // Filenames carry the device's local time; parse them the same way.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let minute = try #require(cal.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 8, minute: 3)))
        let now = minute.addingTimeInterval(180)

        try "=== SCOUT run starting ===\n"
            .write(to: logs.appendingPathComponent("scout-2026-04-20_08-03.log"), atomically: true, encoding: .utf8)
        try """
        === SCOUT run starting ===
        === Another SCOUT session running (PID 4100) — skipping ===
        """.write(to: logs.appendingPathComponent("scout-2026-04-20_08-03-31-4242.log"), atomically: true, encoding: .utf8)
        // A cost row inside both runs' match window belongs to the live run only.
        let iso = ISO8601DateFormatter()
        let costLine = #"{"ts":"\#(iso.string(from: minute.addingTimeInterval(60)))","ts_et":"t","type":"briefing","budget_cap":10,"budget_spent":0.5,"exit_code":0,"source":"session"}"#
        try (costLine + "\n")
            .write(to: logs.appendingPathComponent("usage-tracker.jsonl"), atomically: true, encoding: .utf8)
        try "not a run\n".write(to: logs.appendingPathComponent("failures.log"), atomically: true, encoding: .utf8)

        let result = SessionsStore.loadAll(vault: vault, now: now)

        #expect(result.error == nil)
        #expect(result.runs.map { $0.logPath.lastPathComponent }
                == ["scout-2026-04-20_08-03-31-4242.log", "scout-2026-04-20_08-03.log"])
        #expect(Set(result.runs.map(\.id)).count == 2)
        let skip = result.runs[0]
        let live = result.runs[1]
        #expect(live.status == .running, "a skip in the live run's minute must not orphan or relabel it")
        #expect(live.id == Run.makeId(type: .morningBriefing, startedAt: minute))
        #expect(skip.status == .skippedConcurrency)
        #expect(skip.id == Run.makeId(type: .morningBriefing, startedAt: minute.addingTimeInterval(31), pid: 4242))
        #expect(live.cost == Decimal(string: "0.5"))
        #expect(skip.cost == nil)
    }
}

struct UsageEntryTests {
    @Test func decodesLegacyAndCurrentShapes() throws {
        let legacy = #"{"ts":"2026-04-16T11:02:02Z","ts_et":"2026-04-16 07:02 EDT","type":"morning-briefing","budget_cap":10,"budget_spent":0,"exit_code":0,"source":"runner"}"#
        let current = #"{"ts":"2026-06-12T09:12:02Z","ts_local":"2026-06-12 11:12 CEST","type":"morning-consolidation","budget_cap":5.00,"budget_spent":0,"exit_code":0,"source":"runner"}"#
        let tick = #"{"ts": "2026-06-12T11:10:50.028Z", "type": "consolidation", "scout_mode": "midday-consolidation", "source": "schedule.tick"}"#

        let e1 = try #require(UsageEntry.decode(jsonLine: Data(legacy.utf8)))
        #expect(e1.tsLocal == "2026-04-16 07:02 EDT")
        #expect(e1.budgetCap == 10)

        let e2 = try #require(UsageEntry.decode(jsonLine: Data(current.utf8)))
        #expect(e2.tsLocal == "2026-06-12 11:12 CEST")
        #expect(e2.type == "morning-consolidation")

        let e3 = try #require(UsageEntry.decode(jsonLine: Data(tick.utf8)))
        #expect(e3.source == "schedule.tick")
    }
}

struct ScheduleParserTests {
    @Test func parsesVaultSchedule() {
        let yaml = """
        # comment header
        schema_version: 1

        slots:
          morning-briefing:
            type: briefing
            runner: run-scout.sh
            fires_at_local: "08:03"
            weekdays: [Mon, Tue, Wed, Thu, Fri]
            missed_window_hours: 4
            on_miss: fire
            cooldown_minutes: 60

          dreaming-nightly:
            type: dreaming
            runner: run-dreaming.sh
            fires_at_local: "20:33"
            weekdays: [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
            missed_window_hours: 6
            on_miss: skip
            cooldown_minutes: 120
        """
        let slots = ScheduleParser.parse(text: yaml)
        #expect(slots.count == 2)
        let briefing = slots[0]
        #expect(briefing.key == "morning-briefing")
        #expect(briefing.type == .briefing)
        #expect(briefing.firesAtLocal == "08:03")
        #expect(briefing.weekdays == ["Mon", "Tue", "Wed", "Thu", "Fri"])
        #expect(briefing.onMiss == .fire)
        #expect(briefing.cooldownMinutes == 60)
        #expect(slots[1].type == .dreaming)
        #expect(slots[1].weekdays.count == 7)
    }

    @Test func computesUpcoming() throws {
        let slot = Slot(
            key: "morning-briefing", type: .briefing, runner: "run-scout.sh",
            firesAtLocal: "08:03", weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri"],
            missedWindowHours: 4, onMiss: .fire, cooldownMinutes: 60,
            budgetUsd: nil, tz: nil
        )
        // A Wednesday noon — next fire must be Thursday 08:03.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let wednesdayNoon = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12)))
        let upcoming = UpcomingRunCalculator.upcoming(slots: [slot], from: wednesdayNoon, limit: 3)
        #expect(!upcoming.isEmpty)
        let first = try #require(upcoming.first)
        #expect(cal.component(.weekday, from: first.scheduledAt) == 5) // Thursday
        #expect(cal.component(.hour, from: first.scheduledAt) == 8)
        #expect(cal.component(.minute, from: first.scheduledAt) == 3)
    }
}
