import Foundation

public enum TextFlightParser {
    private static let dateFormats = ["dd/MM/yy", "dd/MM/yyyy", "yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy"]

    public static func parseCandidates(from text: String, suggestions: SuggestionBundle = SuggestionBundle()) -> [ImportCandidate] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { likelyFlightLine($0) }
            .compactMap { parseLine($0, suggestions: suggestions) }
    }

    public static func parseLine(_ line: String, suggestions: SuggestionBundle = SuggestionBundle()) -> ImportCandidate? {
        let tokens = line
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let dateIndex = tokens.firstIndex(where: { parseDate($0) != nil }),
              let date = parseDate(tokens[dateIndex])
        else { return nil }

        var departure = ""
        var arrival = ""
        var aircraftID = ""
        var totalMinutes = 0
        var nightMinutes = 0
        var copilotMinutes = 0
        var picMinutes = 0
        var passengers = 0
        var distance = 0.0

        let upperPlaces = Set(suggestions.places.map { $0.uppercased() })
        let upperAircraft = Set(suggestions.aircraftIDs.map { $0.uppercased() })
        let remaining = tokens.enumerated().filter { $0.offset != dateIndex }.map(\.element)

        for token in remaining {
            let normalized = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;|"))
            let upper = normalized.uppercased()
            if aircraftID.isEmpty && (upperAircraft.contains(upper) || upper.hasPrefix("G-") || upper.hasPrefix("N") || upper.hasPrefix("EI-")) {
                aircraftID = normalized
            } else if departure.isEmpty && isAirportCode(upper, knownPlaces: upperPlaces) {
                departure = upper
            } else if !departure.isEmpty && arrival.isEmpty && isAirportCode(upper, knownPlaces: upperPlaces) {
                arrival = upper
            }

            if totalMinutes == 0, let minutes = parseDuration(normalized), !upper.contains("PIC") && !upper.contains("SIC") && !upper.contains("NIGHT") {
                totalMinutes = minutes
            }
            if upper.contains("PAX"), let count = intSuffix(upper) {
                passengers = count
            }
            if upper.contains("NM"), let value = doublePrefix(upper) {
                distance = value
            }
            if upper.contains("SIC") || upper.contains("COPILOT") || upper.contains("CO-PILOT") {
                copilotMinutes = parseDuration(normalized) ?? copilotMinutes
            }
            if upper.contains("PIC") {
                picMinutes = parseDuration(normalized) ?? picMinutes
            }
            if upper.contains("NIGHT") {
                nightMinutes = parseDuration(normalized) ?? nightMinutes
            }
        }

        guard !departure.isEmpty || !arrival.isEmpty || !aircraftID.isEmpty || totalMinutes > 0 else { return nil }

        let copilotNight = min(copilotMinutes, nightMinutes)
        let flight = FlightEntry(
            date: date,
            departure: departure,
            arrival: arrival,
            aircraftID: aircraftID,
            operation: copilotMinutes > 0 ? "MP" : "SP",
            pilotFunction: copilotMinutes > 0 ? "Co-pilot" : (picMinutes > 0 ? "PIC" : ""),
            totalMinutes: totalMinutes,
            picMinutes: picMinutes,
            copilotMinutes: copilotMinutes,
            copilotDayMinutes: max(0, copilotMinutes - copilotNight),
            copilotNightMinutes: copilotNight,
            nightMinutes: nightMinutes,
            passengerCount: passengers,
            distanceNM: distance,
            remarks: "Imported from document: \(line)"
        )
        let confidence = [departure, arrival, aircraftID].filter { !$0.isEmpty }.count >= 2 && totalMinutes > 0 ? 0.8 : 0.45
        return ImportCandidate(flight: flight, rawText: line, confidence: confidence)
    }

    public static func parseDuration(_ token: String) -> Int? {
        let cleaned = token
            .uppercased()
            .replacingOccurrences(of: "SIC", with: "")
            .replacingOccurrences(of: "PIC", with: "")
            .replacingOccurrences(of: "NIGHT", with: "")
            .replacingOccurrences(of: "HRS", with: "")
            .replacingOccurrences(of: "HR", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :=,;()"))
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":")
            guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            return hours * 60 + minutes
        }
        if let decimal = Double(cleaned), decimal > 0, decimal < 30 {
            return Int((decimal * 60).rounded())
        }
        return nil
    }

    private static func likelyFlightLine(_ line: String) -> Bool {
        parseDate(line.split(separator: " ").first.map(String.init) ?? "") != nil ||
        line.range(of: #"\b[A-Z]{4}\b.*\b[A-Z]{4}\b"#, options: .regularExpression) != nil ||
        line.range(of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, options: .regularExpression) != nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: ",;|"))
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    private static func isAirportCode(_ value: String, knownPlaces: Set<String>) -> Bool {
        knownPlaces.contains(value) || value.range(of: #"^[A-Z]{3,4}$"#, options: .regularExpression) != nil
    }

    private static func intSuffix(_ token: String) -> Int? {
        token.range(of: #"\d+"#, options: .regularExpression).flatMap { Int(token[$0]) }
    }

    private static func doublePrefix(_ token: String) -> Double? {
        token.range(of: #"\d+(\.\d+)?"#, options: .regularExpression).flatMap { Double(token[$0]) }
    }
}

public enum FlightMath {
    public static func distanceNM(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let earthRadiusNM = 3440.065
        let dLat = radians(toLat - fromLat)
        let dLon = radians(toLon - fromLon)
        let lat1 = radians(fromLat)
        let lat2 = radians(toLat)
        let a = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return earthRadiusNM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
