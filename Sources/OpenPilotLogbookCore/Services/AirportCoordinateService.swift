import Foundation

public struct AirportCoordinate: Equatable {
    public var identifier: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
}

public final class AirportCoordinateService {
    public static let shared = AirportCoordinateService()

    private let airportsByCode: [String: AirportCoordinate]

    private init() {
        guard let url = Bundle.module.url(forResource: "airports", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            airportsByCode = [:]
            return
        }
        airportsByCode = Self.loadAirports(from: text)
    }

    public func airport(for code: String) -> AirportCoordinate? {
        airportsByCode[Self.normalized(code)]
    }

    public func coordinate(for code: String) -> (latitude: Double, longitude: Double)? {
        guard let airport = airport(for: code) else { return nil }
        return (airport.latitude, airport.longitude)
    }

    private static func loadAirports(from csv: String) -> [String: AirportCoordinate] {
        var result: [String: AirportCoordinate] = [:]
        var lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return result }
        lines.removeFirst()

        for line in lines {
            let fields = parseCSVLine(line)
            guard fields.count >= 16,
                  let latitude = Double(fields[4]),
                  let longitude = Double(fields[5])
            else { continue }

            let airport = AirportCoordinate(
                identifier: fields[1],
                name: fields[3],
                latitude: latitude,
                longitude: longitude
            )
            for code in [fields[1], fields[12], fields[13], fields[14], fields[15]] {
                let normalized = normalized(code)
                if !normalized.isEmpty {
                    if result[normalized] == nil {
                        result[normalized] = airport
                    }
                }
            }
        }
        return result
    }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(field)
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
