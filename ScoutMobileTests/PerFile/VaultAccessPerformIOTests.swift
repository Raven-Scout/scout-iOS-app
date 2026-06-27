import Testing
import Foundation
@testable import ScoutMobile

/// `performIO` is the async bridge that keeps blocking vault I/O
/// (`NSFileCoordinator`, `ensureDownloaded`) off the Swift cooperative thread
/// pool. These cover the contract the call sites rely on: the work runs and its
/// result/error comes back, and it executes on a background thread rather than
/// the caller's.
@Suite("VaultAccess.performIO")
struct VaultAccessPerformIOTests {

    private func makeVault() throws -> VaultAccess {
        let defaults = try #require(UserDefaults(suiteName: "vault-performio-\(UUID().uuidString)"))
        return VaultAccess(defaults: defaults)
    }

    @Test func returnsValueFromWork() async throws {
        let vault = try makeVault()
        let result = await vault.performIO { 6 * 7 }
        #expect(result == 42)
    }

    @Test func propagatesThrownError() async throws {
        struct Boom: Error {}
        let vault = try makeVault()
        await #expect(throws: Boom.self) {
            try await vault.performIO { throw Boom() }
        }
    }

    @MainActor
    @Test func runsOffTheCallingThread() async throws {
        // Pin the caller to the main actor so the contract is actually exercised:
        // without @MainActor, Swift Testing may already run the test off-main and
        // the assertion below would pass trivially. (`Thread.isMainThread` can't be
        // read directly here — it's unavailable from async contexts — but the
        // @MainActor isolation guarantees this prologue runs on the main thread.)
        let vault = try makeVault()
        // The blocking work must not run on the main thread (that is the whole
        // point of routing through the dedicated queue).
        let ranOnMain = await vault.performIO { Thread.isMainThread }
        #expect(ranOnMain == false)
    }
}
