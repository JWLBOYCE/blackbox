import Foundation
import OpenPilotLogbookCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Smoke test failed: \(message)\n", stderr)
        exit(1)
    }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("BlackboxSmoke-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Blackbox.sqlite"))
let repository = LogbookRepository(paths: paths)
try repository.bootstrapIfNeeded()
let emptySummary = try repository.summary()
expect(emptySummary.flightCount == 0, "expected empty isolated logbook")

let date = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
let entered = FlightEntry(
    sourcePK: 900_001, date: date, departure: "EGLL", arrival: "EGKK", aircraftID: "G-TEST", aircraftType: "A320",
    flightNumber: "TST101", operation: "MP", pilotFunction: "Co-pilot", totalMinutes: 65,
    picMinutes: 5, picDayMinutes: 5, copilotMinutes: 65, copilotDayMinutes: 65,
    instrumentMinutes: 0, crossCountryMinutes: 0, fstdMinutes: 7, pilotFlying: true,
    totalTakeoffs: 4, totalLandings: 5, crewNames: "Casey Captain | Avery Pilot", crewRoles: "Casey Captain=Captain | Avery Pilot=First Officer",
    remarks: "Synthetic smoke flight", signatureName: "Synthetic Signer", signatureReference: "SYN-1"
)
let flightID = try repository.saveDraft(entered)
let saved = try repository.flight(id: flightID)!
expect(saved.pilotFunction == "Co-pilot", "pilot function must not be rewritten")
expect(saved.picMinutes == 5 && saved.picDayMinutes == 5 && saved.copilotMinutes == 65 && saved.copilotDayMinutes == 65, "role times and day/night splits must not be reallocated")
expect(saved.instrumentMinutes == 0 && saved.crossCountryMinutes == 0, "entered zero values must remain zero")
expect(saved.fstdMinutes == 7 && saved.pilotFlying, "mixed entered values must remain intact")
expect(saved.totalTakeoffs == 4 && saved.totalLandings == 5, "entered totals must remain intact")
expect(saved.signatureName == "Synthetic Signer" && saved.signatureReference == "SYN-1", "signatures must persist")

_ = try repository.finalise(saved, acknowledgeWarnings: true)
let finalised = try repository.flight(id: flightID)
expect(finalised?.recordState == .finalised, "entry should finalise")
do {
    _ = try repository.saveDraft(try repository.flight(id: flightID)!)
    expect(false, "finalised entry should reject direct edits")
} catch {}

let amendmentID = try repository.beginAmendment(of: flightID)
var amendment = try repository.flight(id: amendmentID)!
amendment.remarks = "Corrected synthetic note"
_ = try repository.saveDraft(amendment)
amendment = try repository.flight(id: amendmentID)!
_ = try repository.finaliseAmendment(amendment, acknowledgeWarnings: true)
let superseded = try repository.flight(id: flightID)
let finalisedAmendment = try repository.flight(id: amendmentID)
expect(superseded?.recordState == .superseded, "original should remain as superseded")
expect(finalisedAmendment?.recordState == .finalised, "amendment should finalise")

let trashID = try repository.saveDraft(FlightEntry(date: date, remarks: "Recoverable synthetic draft"))
try repository.moveToTrash(id: trashID)
let trashed = try repository.flight(id: trashID)
expect(trashed?.recordState == .trashed, "draft should move to Trash")
try repository.restoreFromTrash(id: trashID)
let restored = try repository.flight(id: trashID)
expect(restored?.recordState == .draft, "trashed draft should restore")

let suggestions = FlightSuggestionEngine.suggestions(for: FlightEntry(date: date, departure: "EGLL", arrival: "EGKK"))
expect(suggestions.contains { $0.field == .distanceNM }, "distance should be offered as a suggestion")

let backup = try EncryptedBackupService.createBackup(database: paths.workingDatabase, destinationFolder: paths.backupFolder, passphrase: "synthetic-passphrase")
let restorePlan = try repository.prepareRestore(from: backup.encryptedBackup, passphrase: "synthetic-passphrase")
expect(restorePlan.integrityMessage.lowercased() == "ok", "restore preview should verify integrity")

let revisions = try repository.revisions(for: amendmentID)
let batches = try repository.operationBatches()
expect(revisions.count >= 2, "amendment should have durable revisions")
expect(batches.isEmpty, "no destructive operation should run implicitly")
print("OpenPilotLogbookCore smoke tests passed with isolated synthetic data.")
