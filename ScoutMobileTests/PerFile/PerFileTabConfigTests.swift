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
