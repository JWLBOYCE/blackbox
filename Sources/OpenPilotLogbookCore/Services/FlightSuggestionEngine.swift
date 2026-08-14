import Foundation

public enum FlightSuggestionEngine {
    public static func validationReport(for flight: FlightEntry) -> FlightValidationReport {
        var issues: [FlightValidationIssue] = []
        let simulator = flight.entryKind == "Simulator"

        let timeValues: [(String, Int)] = [
            ("Total time", flight.totalMinutes), ("PIC", flight.picMinutes), ("PIC day", flight.picDayMinutes),
            ("PIC night", flight.picNightMinutes), ("PICUS", flight.picusMinutes), ("PICUS day", flight.picusDayMinutes),
            ("PICUS night", flight.picusNightMinutes), ("Co-pilot", flight.copilotMinutes), ("Co-pilot day", flight.copilotDayMinutes),
            ("Co-pilot night", flight.copilotNightMinutes), ("Dual", flight.dualMinutes), ("Instructor", flight.instructorMinutes),
            ("Night", flight.nightMinutes), ("Instrument", flight.instrumentMinutes), ("Cross-country", flight.crossCountryMinutes), ("FSTD", flight.fstdMinutes)
        ]
        for (field, value) in timeValues where value < 0 {
            issues.append(.init(field: field, message: "Time cannot be negative.", guidance: "Enter the literal non-negative value from the source record.", severity: .error))
        }
        let countValues: [(String, Int)] = [
            ("Day takeoffs", flight.dayTakeoffs), ("Night takeoffs", flight.nightTakeoffs), ("Total takeoffs", flight.totalTakeoffs),
            ("Day landings", flight.dayLandings), ("Night landings", flight.nightLandings), ("Total landings", flight.totalLandings), ("Passengers", flight.passengerCount)
        ]
        for (field, value) in countValues where value < 0 {
            issues.append(.init(field: field, message: "Count cannot be negative.", guidance: "Enter zero or the recorded count.", severity: .error))
        }

        if !simulator && flight.departure.isEmpty && flight.route.isEmpty {
            issues.append(.init(field: "Departure", message: "Departure is missing.", guidance: "Enter a departure code or retain the draft until it is known."))
        }
        if !simulator && flight.arrival.isEmpty && flight.route.isEmpty {
            issues.append(.init(field: "Arrival", message: "Arrival is missing.", guidance: "Enter an arrival code or retain the draft until it is known."))
        }
        if flight.aircraftID.isEmpty {
            issues.append(.init(field: "Aircraft", message: "Aircraft or device ID is missing.", guidance: "Add the registration, fleet ID, or simulator identifier."))
        }
        if flight.totalMinutes <= 0 && flight.fstdMinutes <= 0 {
            issues.append(.init(field: "Total time", message: "No loggable time is entered.", guidance: "Enter elapsed flight or simulator time."))
        }
        if flight.pilotFunction.isEmpty {
            issues.append(.init(field: "Function", message: "Pilot function is unspecified.", guidance: "Choose the function actually recorded for this entry."))
        }
        let functionTotal = flight.picMinutes + flight.picusMinutes + flight.copilotMinutes + flight.dualMinutes + flight.instructorMinutes + flight.fstdMinutes
        if flight.totalMinutes > 0 && functionTotal == 0 {
            issues.append(.init(field: "Function time", message: "Total time has no corresponding function time.", guidance: "Review the function-time columns; Blackbox will not allocate them automatically."))
        }
        if flight.totalMinutes >= 0 {
            let boundedTimes: [(String, Int)] = [
                ("PIC", flight.picMinutes), ("PIC day", flight.picDayMinutes), ("PIC night", flight.picNightMinutes),
                ("PICUS", flight.picusMinutes), ("PICUS day", flight.picusDayMinutes), ("PICUS night", flight.picusNightMinutes),
                ("Co-pilot", flight.copilotMinutes), ("Co-pilot day", flight.copilotDayMinutes), ("Co-pilot night", flight.copilotNightMinutes),
                ("Dual", flight.dualMinutes), ("Instructor", flight.instructorMinutes), ("Night", flight.nightMinutes),
                ("Instrument", flight.instrumentMinutes), ("Cross-country", flight.crossCountryMinutes), ("FSTD", flight.fstdMinutes)
            ]
            for (field, value) in boundedTimes where value > flight.totalMinutes {
                issues.append(.init(field: field, message: "Time exceeds total time.", guidance: "Review the literal values; Blackbox will not reduce them automatically.", severity: .error))
            }
        }
        if flight.picMinutes > 0 && flight.picDayMinutes + flight.picNightMinutes != flight.picMinutes {
            issues.append(.init(field: "PIC split", message: "PIC day plus night must equal PIC time.", guidance: "Allocate the complete PIC total between day and night before finalising.", severity: .error))
        }
        if flight.picusMinutes > 0 && flight.picusDayMinutes + flight.picusNightMinutes != flight.picusMinutes {
            issues.append(.init(field: "PICUS split", message: "PICUS day plus night must equal PICUS time.", guidance: "Allocate the complete PICUS total between day and night before finalising.", severity: .error))
        }
        if flight.copilotMinutes > 0 && flight.copilotDayMinutes + flight.copilotNightMinutes != flight.copilotMinutes {
            issues.append(.init(field: "Co-pilot split", message: "Co-pilot day plus night must equal co-pilot time.", guidance: "Allocate the complete co-pilot total between day and night before finalising.", severity: .error))
        }
        let selectedFunction = flight.pilotFunction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedRole: (field: String, total: Int, night: Int)? = switch selectedFunction {
        case "pic", "pilot in command": ("PIC", flight.picMinutes, flight.picNightMinutes)
        case "picus": ("PICUS", flight.picusMinutes, flight.picusNightMinutes)
        case "co-pilot", "copilot", "sic": ("Co-pilot", flight.copilotMinutes, flight.copilotNightMinutes)
        default: nil
        }
        if let selectedRole, flight.totalMinutes > 0, selectedRole.total != flight.totalMinutes {
            issues.append(.init(field: "\(selectedRole.field) allocation", message: "Selected function time must equal total time.", guidance: "Allocate the complete sector total to the selected pilot function before finalising.", severity: .error))
        }
        if let selectedRole, selectedRole.total > 0, selectedRole.night != flight.nightMinutes {
            issues.append(.init(field: "\(selectedRole.field) night", message: "Selected function night must equal recorded Night.", guidance: "Re-apply the function allocation after confirming the Night value.", severity: .error))
        }
        if simulator && flight.totalMinutes > 0 && flight.fstdMinutes == 0 {
            issues.append(.init(field: "FSTD", message: "A simulator entry has total time but no FSTD allocation.", guidance: "Enter the recorded FSTD value or retain the draft until it is known."))
        }
        if simulator && flight.totalMinutes >= 0 && flight.fstdMinutes > 0 && flight.fstdMinutes != flight.totalMinutes {
            issues.append(.init(field: "Simulator", message: "Simulator total and FSTD time differ.", guidance: "Review the recorded total and FSTD values; Blackbox will not reconcile them.", severity: .error))
        }
        let airborneSimulatorFacts = flight.picMinutes > 0 || flight.picusMinutes > 0 || flight.copilotMinutes > 0 ||
            flight.nightMinutes > 0 || flight.crossCountryMinutes > 0 || flight.pilotFlying ||
            flight.totalTakeoffs > 0 || flight.totalLandings > 0 || flight.passengerCount > 0 || flight.distanceNM > 0
        if simulator && airborneSimulatorFacts {
            issues.append(.init(field: "Simulator", message: "A simulator entry contains airborne-only facts.", guidance: "Review the entry type and the literal role, night, cross-country, sector, passenger, and distance values.", severity: .error))
        }
        if !simulator && flight.fstdMinutes > 0 && flight.totalMinutes == 0 {
            issues.append(.init(field: "Entry type", message: "A flight entry contains only simulator time.", guidance: "Confirm the entry type and retain the literal values."))
        }
        for (field, value, range) in [
            ("Departure latitude", flight.departureLatitude, -90.0...90.0), ("Arrival latitude", flight.arrivalLatitude, -90.0...90.0),
            ("Departure longitude", flight.departureLongitude, -180.0...180.0), ("Arrival longitude", flight.arrivalLongitude, -180.0...180.0)
        ] where value.map({ !range.contains($0) }) == true {
            issues.append(.init(field: field, message: "Coordinate is outside its valid range.", guidance: "Enter a valid coordinate or clear it.", severity: .error))
        }
        if (flight.departureLatitude == nil) != (flight.departureLongitude == nil) {
            issues.append(.init(field: "Departure coordinates", message: "The coordinate pair is incomplete.", guidance: "Enter both latitude and longitude or clear both values."))
        }
        if (flight.arrivalLatitude == nil) != (flight.arrivalLongitude == nil) {
            issues.append(.init(field: "Arrival coordinates", message: "The coordinate pair is incomplete.", guidance: "Enter both latitude and longitude or clear both values."))
        }
        if flight.recordState != .superseded && flight.amendsFlightID != nil && flight.supersededByFlightID != nil {
            issues.append(.init(field: "Amendment", message: "An amendment cannot also be superseded by itself while being edited.", guidance: "Recreate the amendment from its finalised original.", severity: .error))
        }
        if let id = flight.id, flight.amendsFlightID == id || flight.supersededByFlightID == id {
            issues.append(.init(field: "Amendment", message: "A flight cannot link to itself.", guidance: "Remove the invalid linkage.", severity: .error))
        }
        if (flight.recordState == .draft || flight.recordState == .trashed) && flight.locked {
            issues.append(.init(field: "Record state", message: "A draft or trashed record cannot be locked.", guidance: "Use the explicit record-state workflow.", severity: .error))
        }
        if (flight.recordState == .finalised || flight.recordState == .superseded) && !flight.locked {
            issues.append(.init(field: "Record state", message: "A finalised or superseded record must be locked.", guidance: "Use the explicit finalisation or amendment workflow.", severity: .error))
        }
        if flight.recordState == .superseded && flight.supersededByFlightID == nil {
            issues.append(.init(field: "Record state", message: "A superseded record has no successor.", guidance: "Repair the amendment linkage before finalising another record.", severity: .error))
        }
        if flight.totalTakeoffs != flight.dayTakeoffs + flight.nightTakeoffs {
            issues.append(.init(field: "Takeoffs", message: "Total takeoffs differ from day plus night takeoffs.", guidance: "Keep the entered total or accept the calculated suggestion."))
        }
        if flight.totalLandings != flight.dayLandings + flight.nightLandings {
            issues.append(.init(field: "Landings", message: "Total landings differ from day plus night landings.", guidance: "Keep the entered total or accept the calculated suggestion."))
        }
        return FlightValidationReport(issues: issues)
    }

    public static func suggestions(for flight: FlightEntry) -> [FlightSuggestion] {
        var suggestions: [FlightSuggestion] = []
        let dep = AirportCoordinateService.shared.coordinate(for: flight.departure)
        let arr = AirportCoordinateService.shared.coordinate(for: flight.arrival)

        if flight.departureLatitude == nil, flight.departureLongitude == nil, let dep {
            suggestions.append(.init(field: .departureCoordinates, title: "Departure coordinates", explanation: "Found in Blackbox's bundled airport reference.", currentValue: "Not entered", proposedValue: coordinateText(dep.latitude, dep.longitude), latitude: dep.latitude, longitude: dep.longitude))
        } else if (flight.departureLatitude == nil) != (flight.departureLongitude == nil) {
            suggestions.append(.init(field: .departureCoordinates, title: "Departure coordinates", explanation: "A partially entered coordinate pair is preserved.", currentValue: coordinateText(flight.departureLatitude, flight.departureLongitude), proposedValue: "Unavailable", method: "Bundled airport reference", unavailableReason: "One departure coordinate is already entered. Complete or clear the pair before requesting a suggestion."))
        }
        if flight.arrivalLatitude == nil, flight.arrivalLongitude == nil, let arr {
            suggestions.append(.init(field: .arrivalCoordinates, title: "Arrival coordinates", explanation: "Found in Blackbox's bundled airport reference.", currentValue: "Not entered", proposedValue: coordinateText(arr.latitude, arr.longitude), latitude: arr.latitude, longitude: arr.longitude))
        } else if (flight.arrivalLatitude == nil) != (flight.arrivalLongitude == nil) {
            suggestions.append(.init(field: .arrivalCoordinates, title: "Arrival coordinates", explanation: "A partially entered coordinate pair is preserved.", currentValue: coordinateText(flight.arrivalLatitude, flight.arrivalLongitude), proposedValue: "Unavailable", method: "Bundled airport reference", unavailableReason: "One arrival coordinate is already entered. Complete or clear the pair before requesting a suggestion."))
        }
        let depLat = flight.departureLatitude ?? dep?.latitude
        let depLon = flight.departureLongitude ?? dep?.longitude
        let arrLat = flight.arrivalLatitude ?? arr?.latitude
        let arrLon = flight.arrivalLongitude ?? arr?.longitude
        if flight.distanceNM == 0, let depLat, let depLon, let arrLat, let arrLon {
            let distance = greatCircleNM(depLat, depLon, arrLat, arrLon)
            suggestions.append(.init(field: .distanceNM, title: "Route distance", explanation: "Great-circle distance calculated from airport coordinates.", currentValue: "0 NM", proposedValue: String(format: "%.0f NM", distance), numericValue: distance))
        }
        let takeoffs = flight.dayTakeoffs + flight.nightTakeoffs
        if takeoffs != flight.totalTakeoffs {
            suggestions.append(.init(field: .totalTakeoffs, title: "Total takeoffs", explanation: "Day plus night takeoffs.", currentValue: "\(flight.totalTakeoffs)", proposedValue: "\(takeoffs)", numericValue: Double(takeoffs)))
        }
        let landings = flight.dayLandings + flight.nightLandings
        if landings != flight.totalLandings {
            suggestions.append(.init(field: .totalLandings, title: "Total landings", explanation: "Day plus night landings.", currentValue: "\(flight.totalLandings)", proposedValue: "\(landings)", numericValue: Double(landings)))
        }
        suggestions.append(nightAssessment(for: flight, departure: dep, arrival: arr))
        suggestions.append(roleAssessment(for: flight))
        return suggestions
    }

    public static func prepareBatch(for flight: FlightEntry, selectedSuggestionIDs: Set<String> = []) -> SuggestionBatch {
        let suggestions = suggestions(for: flight)
        return SuggestionBatch(flightID: flight.id, suggestions: suggestions, selectedSuggestionIDs: selectedSuggestionIDs)
    }

    public static func applying(_ batch: SuggestionBatch, to input: FlightEntry) -> FlightEntry {
        batch.suggestions
            .filter { batch.selectedSuggestionIDs.contains($0.id) && $0.isActionable }
            .reduce(input) { applying($1, to: $0) }
    }

    public static func applying(_ suggestion: FlightSuggestion, to input: FlightEntry) -> FlightEntry {
        var flight = input
        switch suggestion.field {
        case .distanceNM:
            if flight.distanceNM == 0 { flight.distanceNM = suggestion.numericValue ?? flight.distanceNM }
        case .departureCoordinates:
            if flight.departureLatitude == nil, flight.departureLongitude == nil {
                flight.departureLatitude = suggestion.latitude
                flight.departureLongitude = suggestion.longitude
            }
        case .arrivalCoordinates:
            if flight.arrivalLatitude == nil, flight.arrivalLongitude == nil {
                flight.arrivalLatitude = suggestion.latitude
                flight.arrivalLongitude = suggestion.longitude
            }
        case .nightMinutes:
            if flight.nightMinutes == 0 { flight.nightMinutes = Int(suggestion.numericValue ?? 0) }
        case .picMinutes:
            if roleValuesAreEmpty(flight) {
                allocateRoleMinutes(Int(suggestion.numericValue ?? 0), to: .picMinutes, in: &flight)
            }
        case .picusMinutes:
            if roleValuesAreEmpty(flight) {
                allocateRoleMinutes(Int(suggestion.numericValue ?? 0), to: .picusMinutes, in: &flight)
            }
        case .copilotMinutes:
            if roleValuesAreEmpty(flight) {
                allocateRoleMinutes(Int(suggestion.numericValue ?? 0), to: .copilotMinutes, in: &flight)
            }
        case .dualMinutes:
            if roleValuesAreEmpty(flight) { flight.dualMinutes = Int(suggestion.numericValue ?? 0) }
        case .instructorMinutes:
            if roleValuesAreEmpty(flight) { flight.instructorMinutes = Int(suggestion.numericValue ?? 0) }
        case .fstdMinutes:
            if roleValuesAreEmpty(flight) { flight.fstdMinutes = Int(suggestion.numericValue ?? 0) }
        case .totalTakeoffs: flight.totalTakeoffs = Int(suggestion.numericValue ?? Double(flight.totalTakeoffs))
        case .totalLandings: flight.totalLandings = Int(suggestion.numericValue ?? Double(flight.totalLandings))
        }
        return flight
    }

    private static func greatCircleNM(_ latitude1: Double, _ longitude1: Double, _ latitude2: Double, _ longitude2: Double) -> Double {
        let radiusNM = 3_440.065
        let lat1 = latitude1 * .pi / 180
        let lat2 = latitude2 * .pi / 180
        let deltaLat = (latitude2 - latitude1) * .pi / 180
        let deltaLon = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radiusNM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func coordinateText(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private static func coordinateText(_ latitude: Double?, _ longitude: Double?) -> String {
        "\(latitude.map { String(format: "%.5f", $0) } ?? "missing"), \(longitude.map { String(format: "%.5f", $0) } ?? "missing")"
    }

    private static func roleValuesAreEmpty(_ flight: FlightEntry) -> Bool {
        [
            flight.picMinutes, flight.picDayMinutes, flight.picNightMinutes,
            flight.picusMinutes, flight.picusDayMinutes, flight.picusNightMinutes,
            flight.copilotMinutes, flight.copilotDayMinutes, flight.copilotNightMinutes,
            flight.dualMinutes, flight.instructorMinutes, flight.fstdMinutes
        ]
            .allSatisfy { $0 == 0 }
    }

    private static func allocateRoleMinutes(_ total: Int, to field: FlightSuggestionField, in flight: inout FlightEntry) {
        let night = min(max(flight.nightMinutes, 0), total)
        let day = total - night
        switch field {
        case .picMinutes:
            flight.picMinutes = total
            flight.picDayMinutes = day
            flight.picNightMinutes = night
        case .picusMinutes:
            flight.picusMinutes = total
            flight.picusDayMinutes = day
            flight.picusNightMinutes = night
        case .copilotMinutes:
            flight.copilotMinutes = total
            flight.copilotDayMinutes = day
            flight.copilotNightMinutes = night
        default:
            break
        }
    }

    private static func nightAssessment(for flight: FlightEntry, departure: (latitude: Double, longitude: Double)?, arrival: (latitude: Double, longitude: Double)?) -> FlightSuggestion {
        let depLat = flight.departureLatitude ?? departure?.latitude
        let depLon = flight.departureLongitude ?? departure?.longitude
        let arrLat = flight.arrivalLatitude ?? arrival?.latitude
        let arrLon = flight.arrivalLongitude ?? arrival?.longitude
        let inputs = ["Departure time: \(LogbookFormatters.isoFormatter.string(from: flight.date))", "Duration: \(flight.totalMinutes) minutes", "Route: \(flight.departure)-\(flight.arrival)"]
        guard flight.nightMinutes == 0 else {
            return .init(field: .nightMinutes, title: "Night allocation", explanation: "Entered night time is preserved.", currentValue: "\(flight.nightMinutes) min", proposedValue: "Unavailable", inputs: inputs, method: "Civil twilight along great-circle route", unavailableReason: "Night time is already non-zero, so Blackbox will not overwrite it.")
        }
        guard flight.entryKind != "Simulator", flight.totalMinutes > 0, let depLat, let depLon, let arrLat, let arrLon else {
            return .init(field: .nightMinutes, title: "Night allocation", explanation: "Requires an airborne flight with duration and both coordinates.", currentValue: "\(flight.nightMinutes) min", proposedValue: "Unavailable", inputs: inputs, method: "Civil twilight along great-circle route", unavailableReason: "Time or coordinates are incomplete, so no unambiguous calculation is possible.")
        }
        let result = SolarDayNightCalculator.nightMinutes(departure: flight.date, durationMinutes: flight.totalMinutes, departureLatitude: depLat, departureLongitude: depLon, arrivalLatitude: arrLat, arrivalLongitude: arrLon)
        guard result > 0 else {
            return .init(field: .nightMinutes, title: "Night allocation", explanation: "The calculated route remains outside night.", currentValue: "0 min", proposedValue: "Unavailable", inputs: inputs, method: "Minute sampling below -6 degrees solar elevation, rounded to 5 minutes", unavailableReason: "The deterministic result is zero, so no change is suggested.")
        }
        return .init(field: .nightMinutes, title: "Night allocation", explanation: "Calculated only from recorded timing and coordinates; acceptance is required.", currentValue: "0 min", proposedValue: "\(result) min", numericValue: Double(result), inputs: inputs, method: "Minute sampling below -6 degrees solar elevation, rounded to 5 minutes", confidence: "High")
    }

    private static func roleAssessment(for flight: FlightEntry) -> FlightSuggestion {
        let normalised = flight.pilotFunction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mapping: [String: FlightSuggestionField] = [
            "pic": .picMinutes,
            "pilot in command": .picMinutes,
            "picus": .picusMinutes,
            "co-pilot": .copilotMinutes,
            "copilot": .copilotMinutes,
            "sic": .copilotMinutes
        ]
        let inputs = ["Pilot function: \(flight.pilotFunction.isEmpty ? "Not entered" : flight.pilotFunction)", "Total time: \(flight.totalMinutes) minutes"]
        guard flight.entryKind != "Simulator", flight.totalMinutes > 0, let field = mapping[normalised] else {
            return .init(field: .picMinutes, title: "Role allocation", explanation: "Only uniquely mapped PIC, PICUS or co-pilot functions are eligible.", currentValue: "Entered role times retained", proposedValue: "Unavailable", inputs: inputs, method: "Exact pilot-function mapping", unavailableReason: "The function is missing, ambiguous, simulator-specific, or intentionally excluded (instructor and dual are never inferred).")
        }
        guard roleValuesAreEmpty(flight) else {
            return .init(field: field, title: "Role allocation", explanation: "Existing role values are pilot-entered facts.", currentValue: "Entered role times retained", proposedValue: "Unavailable", inputs: inputs, method: "Exact pilot-function mapping", unavailableReason: "At least one role value is non-zero, so Blackbox will not overwrite or add an allocation.")
        }
        let title: String
        switch field {
        case .picMinutes: title = "PIC allocation"
        case .picusMinutes: title = "PICUS allocation"
        default: title = "Co-pilot allocation"
        }
        return .init(field: field, title: title, explanation: "The entered function maps uniquely to this role. Acceptance allocates the role total and its day/night split from the recorded Night value.", currentValue: "0 min", proposedValue: "\(flight.totalMinutes) min", numericValue: Double(flight.totalMinutes), inputs: inputs, method: "Exact pilot-function mapping with explicit day/night split", confidence: "High")
    }
}
