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
