import AppKit
import Testing
@testable import OpenPilotLogbook

@Suite("Unsaved draft termination")
@MainActor
struct AppTerminationTests {
    @Test("Save permits termination only after persistence succeeds")
    func saveMustSucceed() {
        var saveAttempts = 0
        let successfulReply = AppDelegate.terminationReply(for: .alertFirstButtonReturn) {
            saveAttempts += 1
            return true
        }
        #expect(successfulReply == .terminateNow)
        #expect(saveAttempts == 1)

        let failedReply = AppDelegate.terminationReply(for: .alertFirstButtonReturn) {
            saveAttempts += 1
            return false
        }
        #expect(failedReply == .terminateCancel)
        #expect(saveAttempts == 2)
    }

    @Test("Cancel preserves the running app without attempting a save")
    func cancelKeepsApplicationOpen() {
        var saveWasCalled = false
        let reply = AppDelegate.terminationReply(for: .alertSecondButtonReturn) {
            saveWasCalled = true
            return true
        }

        #expect(reply == .terminateCancel)
        #expect(!saveWasCalled)
    }

    @Test("Explicit discard permits termination without writing")
    func explicitDiscardPermitsTermination() {
        var saveWasCalled = false
        let reply = AppDelegate.terminationReply(for: .alertThirdButtonReturn) {
            saveWasCalled = true
            return true
        }

        #expect(reply == .terminateNow)
        #expect(!saveWasCalled)
    }
}
