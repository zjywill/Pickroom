import Foundation

/// A place on Earth, stored the way the user picked it rather than the way any
/// one file format spells it.
struct PhotoLocation: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    /// What the map called this point when it was picked. Nothing reads it back
    /// out of a file — EXIF has no field for it — so it is a convenience for
    /// the inspector, not a source of truth.
    var name: String?

    init?(latitude: Double, longitude: Double, name: String? = nil) {
        guard
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }

    var coordinateDisplay: String {
        let lat = abs(latitude).formatted(.number.precision(.fractionLength(5)))
        let lon = abs(longitude).formatted(.number.precision(.fractionLength(5)))
        return "\(lat)° \(latitude >= 0 ? "N" : "S"), \(lon)° \(longitude >= 0 ? "E" : "W")"
    }

    var display: String {
        guard let name, !name.isEmpty else { return coordinateDisplay }
        return name
    }
}

/// GPS coordinates as XMP and EXIF spell them: degrees, then minutes, then a
/// hemisphere letter — never a signed decimal.
enum GPSCoordinateFormat {
    /// `"39,54.2833N"` — the form XMP uses, degrees and decimal minutes.
    static func xmp(_ value: Double, isLatitude: Bool) -> String {
        let magnitude = abs(value)
        let degrees = magnitude.rounded(.down)
        let minutes = (magnitude - degrees) * 60
        let hemisphere = hemisphere(for: value, isLatitude: isLatitude)
        let formattedMinutes = minutes.formatted(
            .number.precision(.fractionLength(4)).grouping(.never)
        )
        return "\(Int(degrees)),\(formattedMinutes)\(hemisphere)"
    }

    /// Parses the XMP form back to a signed decimal, accepting both the
    /// degrees/decimal-minutes and degrees/minutes/seconds spellings.
    static func value(fromXMP text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last, "NSEWnsew".contains(last) else { return nil }

        let numbers = trimmed.dropLast().split(separator: ",").map(String.init)
        guard (2...3).contains(numbers.count) else { return nil }

        let parts = numbers.compactMap(Double.init)
        guard parts.count == numbers.count else { return nil }

        var magnitude = parts[0] + parts[1] / 60
        if parts.count == 3 {
            magnitude += parts[2] / 3_600
        }

        let isNegative = last == "S" || last == "W" || last == "s" || last == "w"
        return isNegative ? -magnitude : magnitude
    }

    static func hemisphere(for value: Double, isLatitude: Bool) -> String {
        if isLatitude {
            return value >= 0 ? "N" : "S"
        }
        return value >= 0 ? "E" : "W"
    }
}
