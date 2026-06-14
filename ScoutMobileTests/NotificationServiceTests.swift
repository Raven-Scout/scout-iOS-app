import Testing
import Foundation
@testable import ScoutMobile

struct NotificationServiceTests {

    private func run(status: RunStatus, durationSeconds: Int?) -> Run {
        Run(
            id: "dreaming-test",
            type: .dreaming,
            runnerScript: "run-dreaming.sh",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil,
            status: status,
            exitCode: status == .success ? 0 : 1,
            durationSeconds: durationSeconds,
            cost: nil,
            budgetCap: nil,
            logPath: URL(fileURLWithPath: ".scout-logs/dreaming-test.log"),
            logSizeBytes: 0,
            errorsDetected: []
        )
    }

    // Regression: a ~10h run (36066s, as recorded in
    // dreaming-2026-06-13_03-06.log) must roll into hours — not render as the
    // misleading "601m 6s" the old minutes-only formatter produced.
    @Test func successBodyRollsLongDurationIntoHours() {
        let body = NotificationService.body(for: run(status: .success, durationSeconds: 36066))
        #expect(body == "Completed successfully in 10h 1m.")
        #expect(!body.contains("601m"))
    }

    @Test func successBodyKeepsMinutesAndSecondsForShortRuns() {
        let body = NotificationService.body(for: run(status: .success, durationSeconds: 530))
        #expect(body == "Completed successfully in 8m 50s.")
    }

    @Test func successBodyWithoutDurationOmitsTiming() {
        let body = NotificationService.body(for: run(status: .success, durationSeconds: nil))
        #expect(body == "Completed successfully.")
    }
}
