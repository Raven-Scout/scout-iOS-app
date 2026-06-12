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
