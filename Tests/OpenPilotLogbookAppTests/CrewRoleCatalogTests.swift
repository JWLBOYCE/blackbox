import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("Crew role catalog")
struct CrewRoleCatalogTests {
    @Test("A persisted PICUS role reopens in the first-officer slot")
    func picusRoundTripsIntoFirstOfficerSlot() {
        #expect(CrewRoleCatalog.menuOptions.filter { $0 == "PICUS" }.count == 1)
        let encoded = FlightEntry.crewRolesText(
            from: ["Synthetic Pilot": "PICUS"],
            names: ["Synthetic Pilot"]
        )
        let decoded = FlightEntry.parseCrewRoles(encoded)
        #expect(decoded["Synthetic Pilot"] == "PICUS")
        #expect(CrewRoleCatalog.slot(for: decoded["Synthetic Pilot"]) == .firstOfficer)
        #expect(CrewRoleCatalog.role(decoded["Synthetic Pilot"], whenAssignedTo: .firstOfficer) == "PICUS")
    }

    @Test("Existing flight-deck slot roles retain their established classification")
    func establishedSlotRolesAreUnchanged() {
        #expect(CrewRoleCatalog.slot(for: "Captain") == .captain)
        #expect(CrewRoleCatalog.slot(for: "PIC") == .captain)
        #expect(CrewRoleCatalog.slot(for: "Training Captain") == .captain)
        #expect(CrewRoleCatalog.slot(for: "First Officer") == .firstOfficer)
        #expect(CrewRoleCatalog.slot(for: "Co-pilot") == .firstOfficer)
        #expect(CrewRoleCatalog.role("Training Captain", whenAssignedTo: .captain) == "Training Captain")
    }

    @Test("Moving a role to a different crew slot applies that slot's neutral default")
    func movingBetweenSlotsUsesNeutralDefaults() {
        #expect(CrewRoleCatalog.role("PICUS", whenAssignedTo: .captain) == "Captain")
        #expect(CrewRoleCatalog.role("PICUS", whenAssignedTo: .other) == "Other crew")
        #expect(CrewRoleCatalog.role("Training Captain", whenAssignedTo: .other) == "Other crew")
        #expect(CrewRoleCatalog.role(nil, whenAssignedTo: .firstOfficer) == "First Officer")
    }
}
