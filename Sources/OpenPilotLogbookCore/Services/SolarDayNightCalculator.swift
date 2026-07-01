import Foundation

public enum SolarDayNightCalculator {
    public static func nightMinutes(
        departure: Date,
        durationMinutes: Int,
        departureLatitude: Double,
        departureLongitude: Double,
        arrivalLatitude: Double,
        arrivalLongitude: Double
    ) -> Int {
        guard durationMinutes > 0 else { return 0 }
        let step = 1
        var night = 0
        for minute in stride(from: 0, to: durationMinutes, by: step) {
            let segment = min(step, durationMinutes - minute)
            let midpoint = Double(minute) + Double(segment) / 2
            let fraction = durationMinutes == 0 ? 0 : midpoint / Double(durationMinutes)
            let position = greatCirclePosition(
                departureLatitude: departureLatitude,
                departureLongitude: departureLongitude,
                arrivalLatitude: arrivalLatitude,
                arrivalLongitude: arrivalLongitude,
                fraction: fraction
            )
            let date = departure.addingTimeInterval(midpoint * 60)
            if solarElevation(date: date, latitude: position.latitude, longitude: position.longitude) < -0.833 {
                night += segment
            }
        }
        return night
    }

    public static func solarElevation(date: Date, latitude: Double, longitude: Double) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(in: timeZone, from: date)
        guard let day = calendar.ordinality(of: .day, in: .year, for: date),
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second
        else { return 0 }

        let decimalHour = Double(hour) + Double(minute) / 60 + Double(second) / 3600
        let gamma = 2 * Double.pi / 365 * (Double(day) - 1 + (decimalHour - 12) / 24)
        let equationOfTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma)
        )
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let trueSolarTime = (decimalHour * 60 + equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        let hourAngleDegrees = trueSolarTime / 4 < 0 ? trueSolarTime / 4 + 180 : trueSolarTime / 4 - 180
        let hourAngle = hourAngleDegrees * Double.pi / 180
        let latitudeRadians = latitude * Double.pi / 180
        let cosineZenith = sin(latitudeRadians) * sin(declination) + cos(latitudeRadians) * cos(declination) * cos(hourAngle)
        let zenith = acos(max(-1, min(1, cosineZenith)))
        return 90 - zenith * 180 / Double.pi
    }

    private static func greatCirclePosition(
        departureLatitude: Double,
        departureLongitude: Double,
        arrivalLatitude: Double,
        arrivalLongitude: Double,
        fraction: Double
    ) -> (latitude: Double, longitude: Double) {
        let lat1 = radians(departureLatitude)
        let lon1 = radians(departureLongitude)
        let lat2 = radians(arrivalLatitude)
        let lon2 = radians(arrivalLongitude)
        let centralAngle = 2 * asin(sqrt(
            pow(sin((lat2 - lat1) / 2), 2) +
            cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        ))

        guard centralAngle > 0.000001 else {
            return (departureLatitude, departureLongitude)
        }

        let a = sin((1 - fraction) * centralAngle) / sin(centralAngle)
        let b = sin(fraction * centralAngle) / sin(centralAngle)
        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)
        let latitude = atan2(z, sqrt(x * x + y * y))
        let longitude = atan2(y, x)
        return (degrees(latitude), normalizedLongitude(degrees(longitude)))
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / Double.pi
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude
        while value < -180 { value += 360 }
        while value > 180 { value -= 360 }
        return value
    }
}
