import Foundation
import Testing
@testable import OpenPilotLogbook

@Suite("UI-test launch root safety")
struct UITestLaunchConfigurationTests {
    @Test("UI test windows are fitted inside the visible screen")
    func testWindowFramesAreFittedAndCentered() {
        let visible = NSRect(x: 0, y: 0, width: 1_024, height: 768)
        let oversized = UITestLaunchConfiguration.fittedTestWindowFrame(
            requestedFrame: NSRect(x: 0, y: 0, width: 1_440, height: 980),
            visibleFrame: visible
        )
        #expect(oversized == NSRect(x: 12, y: 12, width: 1_000, height: 744))

        let regular = UITestLaunchConfiguration.fittedTestWindowFrame(
            requestedFrame: NSRect(x: 0, y: 0, width: 900, height: 700),
            visibleFrame: visible
        )
        #expect(regular.size == NSSize(width: 900, height: 700))
        #expect(regular.midX == visible.midX)
        #expect(regular.midY == visible.midY)
    }

    @Test("Canonical runner temporary direct child is accepted")
    func canonicalRunnerTemporaryDirectChildIsAccepted() throws {
        let syntheticHome = URL(fileURLWithPath: "/Users/Synthetic-Blackbox-Test", isDirectory: true)
        let systemTemporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let runnerTemporaryDirectory = syntheticHome
            .appendingPathComponent("Library/Containers/uk.co.blackbox.logbook.UITests.xctrunner/Data/tmp", isDirectory: true)
        let candidate = runnerTemporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)

        let validated = try UITestLaunchConfiguration.validatedRoot(
            candidate.path,
            temporaryDirectory: systemTemporaryDirectory,
            homeDirectory: syntheticHome
        )

        #expect(validated == candidate.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test("Nested, arbitrarily named, and live roots are rejected")
    func unsafeRootsAreRejected() {
        let syntheticHome = URL(fileURLWithPath: "/Users/Synthetic-Blackbox-Test", isDirectory: true)
        let systemTemporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let runnerTemporaryDirectory = syntheticHome
            .appendingPathComponent("Library/Containers/uk.co.blackbox.logbook.UITests.xctrunner/Data/tmp", isDirectory: true)
        let nestedCandidate = runnerTemporaryDirectory
            .appendingPathComponent("Nested/Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        let arbitraryCandidate = runnerTemporaryDirectory
            .appendingPathComponent("Untrusted-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = syntheticHome
            .appendingPathComponent("Library/Application Support/Blackbox", isDirectory: true)

        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                nestedCandidate.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                arbitraryCandidate.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                liveRoot.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
    }

    @Test("Existing unmarked root is rejected without deleting its contents")
    func existingUnmarkedRootIsRejectedWithoutDeletion() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        let sentinel = root.appendingPathComponent("must-remain.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("synthetic sentinel\n".utf8).write(to: sentinel, options: .atomic)
        defer { try? fileManager.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            try UITestLaunchConfiguration.resetMarkedRoot(root, fileManager: fileManager)
        }
        #expect(fileManager.fileExists(atPath: sentinel.path))
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "synthetic sentinel\n")
    }
}
