import Foundation

// MARK: - Экспорт: GPX и архив своих данных

/// Точка трека из `my_trip_points`: `[долгота, широта, высота, время Unix]`.
public struct ExportedTrackPoint: Decodable, Equatable, Sendable {
    public let longitude: Double
    public let latitude: Double
    public let altitude: Double?
    public let time: Date?

    public init(longitude: Double, latitude: Double, altitude: Double? = nil, time: Date? = nil) {
        self.longitude = longitude
        self.latitude = latitude
        self.altitude = altitude
        self.time = time
    }

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        longitude = try c.decode(Double.self)
        latitude = try c.decode(Double.self)
        altitude = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
        let seconds = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
        // Время 0 — «неизвестно» (старые треки без времени).
        time = seconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }
}

/// GPX 1.1: один трек, один сегмент — открывается в Strava, Komoot, Organic Maps, Google Earth.
public enum GPX {
    public static func document(name: String, points: [ExportedTrackPoint], creator: String = "Dalada") -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="\#(escape(creator))" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <trk>",
            "    <name>\(escape(name))</name>",
            "    <trkseg>",
        ]
        for point in points {
            var line = #"      <trkpt lat="\#(coordinate(point.latitude))" lon="\#(coordinate(point.longitude))">"#
            if let altitude = point.altitude {
                line += "<ele>\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), altitude))</ele>"
            }
            if let time = point.time {
                line += "<time>\(timestamp(time))</time>"
            }
            line += "</trkpt>"
            lines.append(line)
        }
        lines += ["    </trkseg>", "  </trk>", "</gpx>", ""]
        return lines.joined(separator: "\n")
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// «2026-10-01T05:00:00Z».
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

/// Имена файлов экспорта: без символов, которые не любят файловые системы.
public enum ExportFileName {
    /// «Капшагай 2026-10-01.gpx».
    public static func gpx(title: String, date: Date, calendar: Calendar = .current) -> String {
        gpx(title: title, day: day(date, calendar: calendar))
    }

    /// `day` — «2026-10-01» (начало времени из базы).
    public static func gpx(title: String, day: String) -> String {
        "\(safe(title)) \(day.prefix(10)).gpx"
    }

    /// «Dalada 2026-10-06» — папка архива (станет .zip).
    public static func archive(date: Date, calendar: Calendar = .current) -> String {
        "Dalada \(day(date, calendar: calendar))"
    }

    static func safe(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
            .split(separator: " ").joined(separator: " ")
        let trimmed = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Dalada" : trimmed
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Фото из архива `export_my_data` (поле `photos`): путь в хранилище.
public struct ExportedPhoto: Decodable, Sendable, Equatable {
    public let id: UUID
    public let storagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath = "storage_path"
    }
}

/// Поездка из архива: для GPX-файлов рядом с `data.json`.
public struct ExportedTrip: Decodable, Sendable {
    public let id: UUID
    public let title: String?
    /// Как в базе: «2026-10-01T05:00:00+00:00».
    public let startedAt: String
    public let track: [ExportedTrackPoint]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startedAt = "started_at"
        case track
    }
}

/// Из архива — только то, что нужно, чтобы разложить его по файлам.
public struct ExportOutline: Decodable, Sendable {
    public let trips: [ExportedTrip]
    public let photos: [ExportedPhoto]

    public static func decode(_ data: Data) throws -> ExportOutline {
        try JSONDecoder().decode(ExportOutline.self, from: data)
    }

    /// Имена GPX-файлов поездок без повторов: одинаковые названия в один день получают «(2)».
    public func gpxFileNames() -> [UUID: String] {
        var used: [String: Int] = [:]
        var names: [UUID: String] = [:]
        for trip in trips where !trip.track.isEmpty {
            let base = ExportFileName.gpx(title: trip.title ?? "", day: trip.startedAt)
            let count = (used[base] ?? 0) + 1
            used[base] = count
            names[trip.id] = count == 1 ? base : base.replacingOccurrences(of: ".gpx", with: " (\(count)).gpx")
        }
        return names
    }
}
