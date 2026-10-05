import Foundation
import Testing
@testable import DaladaCore

@Suite("Weather")
struct WeatherTests {
    /// 5 октября 2026, 12:00 UTC = 17:00 в Алматы (+5).
    private let now = Date(timeIntervalSince1970: 1_791_201_600)

    /// Ответ Open-Meteo (`timeformat=unixtime`): давление сутки назад 918, сейчас 914; дни — с 3-го по 7-е
    /// по местному времени (полночь в UTC+5 — 19:00 UTC накануне).
    private var fixture: Data {
        let hour = 3600.0
        let n = now.timeIntervalSince1970
        let localMidnight = { (day: Int) in 1_791_140_400.0 + Double(day) * 86_400 } // 5 октября 00:00 +5
        let json = """
        {
          "latitude": 43.9, "longitude": 77.0, "utc_offset_seconds": 18000, "timezone": "Asia/Almaty",
          "current": {"time": \(n), "temperature_2m": 18.34, "weather_code": 2, "wind_speed_10m": 3.12,
                      "wind_direction_10m": 44, "wind_gusts_10m": 6.2, "surface_pressure": 914.0},
          "hourly": {
            "time": [\(n - 25 * hour), \(n - 24 * hour), \(n - 12 * hour), \(n), \(n + hour)],
            "surface_pressure": [918.4, 918.0, null, 914.0, 913.8]
          },
          "daily": {
            "time": [\(localMidnight(-2)), \(localMidnight(-1)), \(localMidnight(0)), \(localMidnight(1)), \(localMidnight(2))],
            "weather_code": [0, 3, 2, 61, null],
            "temperature_2m_max": [20, 19, 21, 15, 12],
            "temperature_2m_min": [8, 7, 9, 6, 4],
            "precipitation_sum": [0, 0, 0, 5.4, 1.2],
            "wind_speed_10m_max": [4, 5, 6, 9, 7],
            "sunrise": [null, null, \(localMidnight(0) + 7 * hour), \(localMidnight(1) + 7 * hour), null],
            "sunset": [null, null, \(localMidnight(0) + 18.5 * hour), null, null]
          }
        }
        """
        return Data(json.utf8)
    }

    @Test func decodesOpenMeteoResponse() throws {
        let forecast = try OpenMeteo.forecast(from: fixture, fetchedAt: now)
        #expect(forecast.utcOffsetSeconds == 18000)
        #expect(forecast.current.temperature == 18.34)
        #expect(forecast.current.windDirection == 44)
        #expect(forecast.current.code == 2)
        #expect(forecast.pressure.count == 4) // null пропущен
        #expect(forecast.days.count == 5)
        #expect(forecast.days[3].code == 61)
        #expect(forecast.days[4].code == nil)
        #expect(forecast.days[2].sunrise == Date(timeIntervalSince1970: 1_791_140_400 + 7 * 3600))
    }

    @Test func pressureTrendOverADay() throws {
        let forecast = try OpenMeteo.forecast(from: fixture, fetchedAt: now)
        #expect(forecast.pressureChange(before: now) == -4)
        #expect(forecast.pressureTrend(at: now) == .falling)
        #expect(PressureTrend(delta: 1.5) == .steady)
        #expect(PressureTrend(delta: 2) == .rising)
        // Сутки назад точки нет ближе полутора часов — сравнивать не с чем.
        #expect(forecast.pressureChange(before: now.addingTimeInterval(-6 * 3600)) == nil)
    }

    @Test func upcomingDaysUseLocalDate() throws {
        let forecast = try OpenMeteo.forecast(from: fixture, fetchedAt: now)
        let days = forecast.upcomingDays(from: now)
        #expect(days.count == 3)
        #expect(days.first?.date == Date(timeIntervalSince1970: 1_791_140_400))
        // В 23:30 по Алматы — всё ещё 5 октября.
        #expect(forecast.upcomingDays(from: now.addingTimeInterval(6.5 * 3600)).first?.date == days.first?.date)
        #expect(forecast.isFresh(at: now.addingTimeInterval(10 * 60)))
        #expect(!forecast.isFresh(at: now.addingTimeInterval(40 * 60)))
    }

    @Test func kindsUnitsAndCompass() {
        #expect(WeatherKind(code: 0) == .clear)
        #expect(WeatherKind(code: 2) == .partlyCloudy)
        #expect(WeatherKind(code: 45) == .fog)
        #expect(WeatherKind(code: 53) == .drizzle)
        #expect(WeatherKind(code: 63) == .rain)
        #expect(WeatherKind(code: 86) == .snow)
        #expect(WeatherKind(code: 81) == .showers)
        #expect(WeatherKind(code: 95) == .thunderstorm)
        #expect(WeatherKind(code: 100) == nil)
        #expect(WeatherUnits.millimetersOfMercury(1013.25) == 760)
        #expect(WeatherUnits.millimetersOfMercury(918.4) == 689)
        #expect(WeatherUnits.compassSector(0) == 0)
        #expect(WeatherUnits.compassSector(44) == 1)
        #expect(WeatherUnits.compassSector(180) == 4)
        #expect(WeatherUnits.compassSector(350) == 0)
        #expect(WeatherUnits.compassSector(-45) == 7)
    }

    @Test func snapshotForReportFitsServerLimits() throws {
        let snapshot = WeatherSnapshot(temperature: 18.34, windSpeed: 3.16, windGusts: 200, windDirection: 44.4, pressure: 914.04, code: 2)
        let report = snapshot.forReport
        #expect(report.temperature == 18.3)
        #expect(report.windSpeed == 3.2)
        #expect(report.windGusts == nil)
        #expect(report.windDirection == 44)
        #expect(report.pressure == 914)
        #expect(report.code == 2)

        var conditions = CheckinConditions(bite: .good)
        conditions.weather = report
        let decoded = try JSONDecoder().decode(CheckinConditions.self, from: JSONEncoder().encode(conditions))
        #expect(decoded == conditions)
        #expect(!decoded.isEmpty)
        #expect(CheckinConditions(weather: report).isEmpty)

        // Чужие значения не ломают отчёт.
        let junk = #"{"bite": "good", "weather": {"temperature": "тепло", "pressure": 914}}"#
        let parsed = try JSONDecoder().decode(CheckinConditions.self, from: Data(junk.utf8))
        #expect(parsed.weather == WeatherSnapshot(pressure: 914))
        let empty = try JSONDecoder().decode(CheckinConditions.self, from: Data(#"{"weather": {}}"#.utf8))
        #expect(empty.weather == nil)
    }

    @Test func requestRoundsCoordinates() {
        let url = OpenMeteo.forecastURL(for: GeoPoint(latitude: 43.90461, longitude: 77.04512))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "latitude" }?.value == "43.90")
        #expect(query.first { $0.name == "longitude" }?.value == "77.05")
        #expect(query.first { $0.name == "timeformat" }?.value == "unixtime")
    }
}
