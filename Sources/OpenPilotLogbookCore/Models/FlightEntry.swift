import Foundation

public struct FlightEntry: Identifiable, Hashable, Codable {
    public var id: Int64?
    public var sourcePK: Int64?
    public var date: Date
    public var departure: String
    public var arrival: String
    public var route: String
    public var aircraftID: String
    public var aircraftType: String
    public var flightNumber: String
    public var operation: String
    public var entryKind: String
    public var pilotFunction: String
    public var totalMinutes: Int
    public var picMinutes: Int
    public var picDayMinutes: Int
    public var picNightMinutes: Int
    public var picusMinutes: Int
    public var picusDayMinutes: Int
    public var picusNightMinutes: Int
    public var copilotMinutes: Int
    public var copilotDayMinutes: Int
    public var copilotNightMinutes: Int
    public var dualMinutes: Int
    public var instructorMinutes: Int
    public var nightMinutes: Int
    public var instrumentMinutes: Int
    public var crossCountryMinutes: Int
    public var fstdMinutes: Int
    public var pilotFlying: Bool
    public var dayTakeoffs: Int
    public var nightTakeoffs: Int
    public var totalTakeoffs: Int
    public var dayLandings: Int
    public var nightLandings: Int
    public var totalLandings: Int
    public var passengerCount: Int
    public var distanceNM: Double
    public var crewNames: String
    public var crewRoles: String
    public var departureLatitude: Double?
    public var departureLongitude: Double?
    public var arrivalLatitude: Double?
    public var arrivalLongitude: Double?
    public var remarks: String
    public var signatureName: String
    public var signatureReference: String
    public var locked: Bool

    public init(
        id: Int64? = nil,
        sourcePK: Int64? = nil,
        date: Date = Date(),
        departure: String = "",
        arrival: String = "",
        route: String = "",
        aircraftID: String = "",
        aircraftType: String = "",
        flightNumber: String = "",
        operation: String = "SP",
        entryKind: String = "Flight",
        pilotFunction: String = "",
        totalMinutes: Int = 0,
        picMinutes: Int = 0,
        picDayMinutes: Int = 0,
        picNightMinutes: Int = 0,
        picusMinutes: Int = 0,
        picusDayMinutes: Int = 0,
        picusNightMinutes: Int = 0,
        copilotMinutes: Int = 0,
        copilotDayMinutes: Int = 0,
        copilotNightMinutes: Int = 0,
        dualMinutes: Int = 0,
        instructorMinutes: Int = 0,
        nightMinutes: Int = 0,
        instrumentMinutes: Int = 0,
        crossCountryMinutes: Int = 0,
        fstdMinutes: Int = 0,
        pilotFlying: Bool = false,
        dayTakeoffs: Int = 0,
        nightTakeoffs: Int = 0,
        totalTakeoffs: Int = 0,
        dayLandings: Int = 0,
        nightLandings: Int = 0,
        totalLandings: Int = 0,
        passengerCount: Int = 0,
        distanceNM: Double = 0,
        crewNames: String = "",
        crewRoles: String = "",
        departureLatitude: Double? = nil,
        departureLongitude: Double? = nil,
        arrivalLatitude: Double? = nil,
        arrivalLongitude: Double? = nil,
        remarks: String = "",
        signatureName: String = "",
        signatureReference: String = "",
        locked: Bool = false
    ) {
        self.id = id
        self.sourcePK = sourcePK
        self.date = date
        self.departure = departure
        self.arrival = arrival
        self.route = route
        self.aircraftID = aircraftID
        self.aircraftType = aircraftType
        self.flightNumber = flightNumber
        self.operation = operation
        self.entryKind = entryKind
        self.pilotFunction = pilotFunction
        self.totalMinutes = totalMinutes
        self.picMinutes = picMinutes
        self.picDayMinutes = picDayMinutes
        self.picNightMinutes = picNightMinutes
        self.picusMinutes = picusMinutes
        self.picusDayMinutes = picusDayMinutes
        self.picusNightMinutes = picusNightMinutes
        self.copilotMinutes = copilotMinutes
        self.copilotDayMinutes = copilotDayMinutes
        self.copilotNightMinutes = copilotNightMinutes
        self.dualMinutes = dualMinutes
        self.instructorMinutes = instructorMinutes
        self.nightMinutes = nightMinutes
        self.instrumentMinutes = instrumentMinutes
        self.crossCountryMinutes = crossCountryMinutes
        self.fstdMinutes = fstdMinutes
        self.pilotFlying = pilotFlying
        self.dayTakeoffs = dayTakeoffs
        self.nightTakeoffs = nightTakeoffs
        self.totalTakeoffs = totalTakeoffs
        self.dayLandings = dayLandings
        self.nightLandings = nightLandings
        self.totalLandings = totalLandings
        self.passengerCount = passengerCount
        self.distanceNM = distanceNM
        self.crewNames = crewNames
        self.crewRoles = crewRoles
        self.departureLatitude = departureLatitude
        self.departureLongitude = departureLongitude
        self.arrivalLatitude = arrivalLatitude
        self.arrivalLongitude = arrivalLongitude
        self.remarks = remarks
        self.signatureName = signatureName
        self.signatureReference = signatureReference
        self.locked = locked
    }

    public var wrappedID: Int64 { id ?? -1 }
    public var flyingMinutes: Int {
        max(0, totalMinutes - fstdMinutes)
    }

    public var flyingInstrumentMinutes: Int {
        max(0, instrumentMinutes - fstdMinutes)
    }

    public var arrivalDate: Date {
        date.addingTimeInterval(TimeInterval(totalMinutes * 60))
    }

    public var routeDisplay: String {
        if !departure.isEmpty || !arrival.isEmpty {
            return [departure, arrival].filter { !$0.isEmpty }.joined(separator: " -> ")
        }
        return route
    }

    public var hasMapCoordinates: Bool {
        departureLatitude != nil && departureLongitude != nil && arrivalLatitude != nil && arrivalLongitude != nil
    }

    public var crewNameList: [String] {
        Self.splitCrewNames(crewNames)
    }

    public var crewRoleMap: [String: String] {
        Self.parseCrewRoles(crewRoles)
    }

    public static func splitCrewNames(_ text: String) -> [String] {
        let separatorSet = CharacterSet(charactersIn: "|;/")
        return text
            .components(separatedBy: separatorSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func parseCrewRoles(_ text: String) -> [String: String] {
        var roles: [String: String] = [:]
        for part in text.components(separatedBy: "|") {
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty {
                roles[pieces[0]] = pieces[1]
            }
        }
        return roles
    }

    public static func crewRolesText(from roles: [String: String], names: [String]) -> String {
        names.compactMap { name in
            guard let role = roles[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty else { return nil }
            return "\(name)=\(role)"
        }
        .joined(separator: " | ")
    }
}

public struct LogbookSummary: Equatable {
    public var flightCount: Int = 0
    public var totalMinutes: Int = 0
    public var picMinutes: Int = 0
    public var picusMinutes: Int = 0
    public var picusDayMinutes: Int = 0
    public var picusNightMinutes: Int = 0
    public var copilotMinutes: Int = 0
    public var copilotDayMinutes: Int = 0
    public var copilotNightMinutes: Int = 0
    public var nightMinutes: Int = 0
    public var instrumentMinutes: Int = 0
    public var crossCountryMinutes: Int = 0
    public var fstdMinutes: Int = 0
    public var landings: Int = 0
    public var passengers: Int = 0
    public var distanceNM: Double = 0
    public var lastFlightDate: Date?

    public init(
        flightCount: Int = 0,
        totalMinutes: Int = 0,
        picMinutes: Int = 0,
        picusMinutes: Int = 0,
        picusDayMinutes: Int = 0,
        picusNightMinutes: Int = 0,
        copilotMinutes: Int = 0,
        copilotDayMinutes: Int = 0,
        copilotNightMinutes: Int = 0,
        nightMinutes: Int = 0,
        instrumentMinutes: Int = 0,
        crossCountryMinutes: Int = 0,
        fstdMinutes: Int = 0,
        landings: Int = 0,
        passengers: Int = 0,
        distanceNM: Double = 0,
        lastFlightDate: Date? = nil
    ) {
        self.flightCount = flightCount
        self.totalMinutes = totalMinutes
        self.picMinutes = picMinutes
        self.picusMinutes = picusMinutes
        self.picusDayMinutes = picusDayMinutes
        self.picusNightMinutes = picusNightMinutes
        self.copilotMinutes = copilotMinutes
        self.copilotDayMinutes = copilotDayMinutes
        self.copilotNightMinutes = copilotNightMinutes
        self.nightMinutes = nightMinutes
        self.instrumentMinutes = instrumentMinutes
        self.crossCountryMinutes = crossCountryMinutes
        self.fstdMinutes = fstdMinutes
        self.landings = landings
        self.passengers = passengers
        self.distanceNM = distanceNM
        self.lastFlightDate = lastFlightDate
    }
}

public struct AircraftSummary: Identifiable, Equatable {
    public var id: String { aircraftID.isEmpty ? aircraftType : aircraftID }
    public var aircraftID: String
    public var aircraftType: String
    public var flightCount: Int
    public var totalMinutes: Int
    public var landings: Int

    public init(aircraftID: String, aircraftType: String, flightCount: Int, totalMinutes: Int, landings: Int) {
        self.aircraftID = aircraftID
        self.aircraftType = aircraftType
        self.flightCount = flightCount
        self.totalMinutes = totalMinutes
        self.landings = landings
    }
}

public struct TypeSummary: Identifiable, Equatable {
    public var id: String { aircraftType.isEmpty ? "Unknown" : aircraftType }
    public var aircraftType: String
    public var flightCount: Int
    public var totalMinutes: Int
    public var copilotDayMinutes: Int
    public var copilotNightMinutes: Int
    public var distanceNM: Double

    public init(aircraftType: String, flightCount: Int, totalMinutes: Int, copilotDayMinutes: Int, copilotNightMinutes: Int, distanceNM: Double) {
        self.aircraftType = aircraftType
        self.flightCount = flightCount
        self.totalMinutes = totalMinutes
        self.copilotDayMinutes = copilotDayMinutes
        self.copilotNightMinutes = copilotNightMinutes
        self.distanceNM = distanceNM
    }
}

public struct PersonSummary: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var flightCount: Int
    public var totalMinutes: Int

    public init(name: String, flightCount: Int, totalMinutes: Int) {
        self.name = name
        self.flightCount = flightCount
        self.totalMinutes = totalMinutes
    }
}

public struct PlaceVisitSummary: Identifiable, Equatable {
    public var id: String { identifier }
    public var identifier: String
    public var name: String
    public var departures: Int
    public var arrivals: Int

    public init(identifier: String, name: String, departures: Int, arrivals: Int) {
        self.identifier = identifier
        self.name = name
        self.departures = departures
        self.arrivals = arrivals
    }
}

public struct MapRoute: Identifiable, Equatable {
    public var id: Int64
    public var departure: String
    public var arrival: String
    public var departureLatitude: Double
    public var departureLongitude: Double
    public var arrivalLatitude: Double
    public var arrivalLongitude: Double
    public var distanceNM: Double

    public init(id: Int64, departure: String, arrival: String, departureLatitude: Double, departureLongitude: Double, arrivalLatitude: Double, arrivalLongitude: Double, distanceNM: Double) {
        self.id = id
        self.departure = departure
        self.arrival = arrival
        self.departureLatitude = departureLatitude
        self.departureLongitude = departureLongitude
        self.arrivalLatitude = arrivalLatitude
        self.arrivalLongitude = arrivalLongitude
        self.distanceNM = distanceNM
    }
}

public struct ImportCandidate: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var flight: FlightEntry
    public var rawText: String
    public var confidence: Double

    public init(flight: FlightEntry, rawText: String, confidence: Double = 0.6) {
        self.flight = flight
        self.rawText = rawText
        self.confidence = confidence
    }
}

public struct SuggestionBundle: Equatable {
    public var aircraftIDs: [String]
    public var aircraftTypes: [String]
    public var places: [String]
    public var people: [String]

    public init(aircraftIDs: [String] = [], aircraftTypes: [String] = [], places: [String] = [], people: [String] = []) {
        self.aircraftIDs = aircraftIDs
        self.aircraftTypes = aircraftTypes
        self.places = places
        self.people = people
    }
}

public struct ComplianceIssue: Identifiable, Equatable {
    public var id: String { "\(field)-\(flightID)" }
    public var flightID: Int64
    public var date: Date
    public var field: String
    public var message: String
    public var guidance: String

    public init(flightID: Int64, date: Date, field: String, message: String, guidance: String = "") {
        self.flightID = flightID
        self.date = date
        self.field = field
        self.message = message
        self.guidance = guidance
    }
}

public struct ComplianceSnapshot: Equatable {
    public var issues: [ComplianceIssue] = []
    public var checkedFlights: Int = 0
    public var caaExportReady: Bool { issues.isEmpty && checkedFlights > 0 }

    public init(issues: [ComplianceIssue] = [], checkedFlights: Int = 0) {
        self.issues = issues
        self.checkedFlights = checkedFlights
    }
}

public struct LogTenComparisonSummary: Equatable {
    public var flightCount: Int
    public var totalMinutes: Int
    public var picMinutes: Int
    public var copilotMinutes: Int
    public var copilotDayMinutes: Int
    public var copilotNightMinutes: Int
    public var nightMinutes: Int
    public var landings: Int
    public var distanceNM: Double

    public init(
        flightCount: Int = 0,
        totalMinutes: Int = 0,
        picMinutes: Int = 0,
        copilotMinutes: Int = 0,
        copilotDayMinutes: Int = 0,
        copilotNightMinutes: Int = 0,
        nightMinutes: Int = 0,
        landings: Int = 0,
        distanceNM: Double = 0
    ) {
        self.flightCount = flightCount
        self.totalMinutes = totalMinutes
        self.picMinutes = picMinutes
        self.copilotMinutes = copilotMinutes
        self.copilotDayMinutes = copilotDayMinutes
        self.copilotNightMinutes = copilotNightMinutes
        self.nightMinutes = nightMinutes
        self.landings = landings
        self.distanceNM = distanceNM
    }
}

public struct LogTenComparisonIssue: Identifiable, Equatable {
    public var id: String { "\(sourcePK)-\(field)" }
    public var sourcePK: Int64
    public var date: Date
    public var route: String
    public var field: String
    public var logTenValue: String
    public var blackboxValue: String

    public init(sourcePK: Int64, date: Date, route: String, field: String, logTenValue: String, blackboxValue: String) {
        self.sourcePK = sourcePK
        self.date = date
        self.route = route
        self.field = field
        self.logTenValue = logTenValue
        self.blackboxValue = blackboxValue
    }
}

public struct LogTenComparisonSnapshot: Equatable {
    public var sourcePath: String
    public var sourceIsLiveLogTen: Bool
    public var logTen: LogTenComparisonSummary
    public var blackboxImported: LogTenComparisonSummary
    public var blackboxAll: LogTenComparisonSummary
    public var blackboxOnly: LogTenComparisonSummary
    public var missingInBlackbox: Int
    public var missingInLogTen: Int
    public var issues: [LogTenComparisonIssue]

    public var importedRowsMatch: Bool {
        missingInBlackbox == 0 && missingInLogTen == 0 && issues.isEmpty
    }

    public init(
        sourcePath: String = "",
        sourceIsLiveLogTen: Bool = false,
        logTen: LogTenComparisonSummary = LogTenComparisonSummary(),
        blackboxImported: LogTenComparisonSummary = LogTenComparisonSummary(),
        blackboxAll: LogTenComparisonSummary = LogTenComparisonSummary(),
        blackboxOnly: LogTenComparisonSummary = LogTenComparisonSummary(),
        missingInBlackbox: Int = 0,
        missingInLogTen: Int = 0,
        issues: [LogTenComparisonIssue] = []
    ) {
        self.sourcePath = sourcePath
        self.sourceIsLiveLogTen = sourceIsLiveLogTen
        self.logTen = logTen
        self.blackboxImported = blackboxImported
        self.blackboxAll = blackboxAll
        self.blackboxOnly = blackboxOnly
        self.missingInBlackbox = missingInBlackbox
        self.missingInLogTen = missingInLogTen
        self.issues = issues
    }
}

public struct RecencySnapshot: Equatable {
    public var hoursLast12Months: Int
    public var hoursLast90Days: Int
    public var landingsLast90Days: Int
    public var nightLandingsLast90Days: Int
    public var instrumentLast90Days: Int
    public var daysSinceLastLanding: Int?
    public var daysSinceLastNightLanding: Int?

    public init(
        hoursLast12Months: Int = 0,
        hoursLast90Days: Int = 0,
        landingsLast90Days: Int = 0,
        nightLandingsLast90Days: Int = 0,
        instrumentLast90Days: Int = 0,
        daysSinceLastLanding: Int? = nil,
        daysSinceLastNightLanding: Int? = nil
    ) {
        self.hoursLast12Months = hoursLast12Months
        self.hoursLast90Days = hoursLast90Days
        self.landingsLast90Days = landingsLast90Days
        self.nightLandingsLast90Days = nightLandingsLast90Days
        self.instrumentLast90Days = instrumentLast90Days
        self.daysSinceLastLanding = daysSinceLastLanding
        self.daysSinceLastNightLanding = daysSinceLastNightLanding
    }
}

public struct DuplicateFlightGroup: Identifiable, Equatable {
    public var id: String
    public var flights: [FlightEntry]

    public init(id: String, flights: [FlightEntry]) {
        self.id = id
        self.flights = flights
    }
}

public struct AirportOverride: Identifiable, Equatable {
    public var id: String { identifier }
    public var identifier: String
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(identifier: String, name: String, latitude: Double, longitude: Double) {
        self.identifier = identifier
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct BackupResult: Equatable {
    public var encryptedBackup: URL
    public var manifest: URL

    public init(encryptedBackup: URL, manifest: URL) {
        self.encryptedBackup = encryptedBackup
        self.manifest = manifest
    }
}
