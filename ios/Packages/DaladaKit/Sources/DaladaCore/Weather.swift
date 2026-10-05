import Foundation

// MARK: - Погода у места

/// Снимок погоды: сейчас у места или в момент отчёта (`conditions.weather`). Давление — у земли
/// (как показывает барометр на месте), а не приведённое к уровню моря.
public struct WeatherSnapshot: Codable, Equatable, Hashable, Sendable {
    /// °C.
    public var temperature: Double?
    /// м/с.
    public var windSpeed: Double?
    /// м/с.
    public var windGusts: Double?
    /// Откуда дует, градусы (0 — с севера).
    public var windDirection: Double?
    /// гПа.
    public var pressure: Double?
    /// Код погоды WMO.
    public var code: Int?

    public init(
        temperature: Double? = nil,
        windSpeed: Double? = nil,
        windGusts: Double? = nil,
        windDirection: Double? = nil,
        pressure: Double? = nil,
        code: Int? = nil
    ) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.windGusts = windGusts
        self.windDirection = windDirection
        self.pressure = pressure
        self.code = code
    }

    enum CodingKeys: String, CodingKey {
        case temperature
        case windSpeed = "wind_speed"
        case windGusts = "wind_gusts"
        case windDirection = "wind_direction"
        case pressure
        case code
    }

    /// Чужие или испорченные значения не ломают разбор отчёта — поле просто пустое.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try? c.decodeIfPresent(Double.self, forKey: .temperature)
        windSpeed = try? c.decodeIfPresent(Double.self, forKey: .windSpeed)
        windGusts = try? c.decodeIfPresent(Double.self, forKey: .windGusts)
        windDirection = try? c.decodeIfPresent(Double.self, forKey: .windDirection)
        pressure = try? c.decodeIfPresent(Double.self, forKey: .pressure)
        code = try? c.decodeIfPresent(Int.self, forKey: .code)
    }

    public var isEmpty: Bool {
        temperature == nil && windSpeed == nil && pressure == nil && code == nil
    }

    /// Для отчёта: округлённые значения в пределах, которые принимает сервер
    /// (`private.weather_snapshot_valid`); выпавшие за пределы — без них.
    public var forReport: WeatherSnapshot {
        func rounded(_ value: Double?, _ range: ClosedRange<Double>, places: Double = 10) -> Double? {
            guard let value, range.contains(value) else { return nil }
            return (value * places).rounded() / places
        }
        return WeatherSnapshot(
            temperature: rounded(temperature, -70...60),
            windSpeed: rounded(windSpeed, 0...100),
            windGusts: rounded(windGusts, 0...150),
            windDirection: rounded(windDirection, 0...360, places: 1),
            pressure: rounded(pressure, 500...1100),
            code: code.flatMap { (0...99).contains($0) ? $0 : nil }
        )
    }
}

/// Вид погоды по коду WMO — для значка и подписи.
public enum WeatherKind: String, CaseIterable, Sendable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm

    public init?(code: Int?) {
        guard let code else { return nil }
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67: self = .rain
        case 71...77, 85, 86: self = .snow
        case 80...82: self = .showers
        case 95...99: self = .thunderstorm
        default: return nil
        }
    }

    public var titleKey: String { "weather.kind.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .clear: "sun.max"
        case .partlyCloudy: "cloud.sun"
        case .cloudy: "cloud"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .showers: "cloud.heavyrain"
        case .thunderstorm: "cloud.bolt.rain"
        }
    }
}

/// Куда меняется давление: рыбаки смотрят именно на это.
public enum PressureTrend: String, Sendable {
    case rising
    case falling
    case steady

    /// Меньше 2 гПа (≈1,5 мм) за сутки — стабильно.
    public static let threshold = 2.0

    public init(delta: Double) {
        if delta >= Self.threshold {
            self = .rising
        } else if delta <= -Self.threshold {
            self = .falling
        } else {
            self = .steady
        }
    }

    public var titleKey: String { "weather.trend.\(rawValue)" }

    public var systemImage: String {
        switch self {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .steady: "arrow.right"
        }
    }
}

/// Давление в момент времени (почасовой ряд прогноза).
public struct PressurePoint: Codable, Equatable, Hashable, Sendable {
    public let time: Date
    /// гПа.
    public let pressure: Double

    public init(time: Date, pressure: Double) {
        self.time = time
        self.pressure = pressure
    }
}

/// День прогноза.
public struct ForecastDay: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Полночь этого дня по местному времени места.
    public let date: Date
    public let code: Int?
    public let temperatureMin: Double?
    public let temperatureMax: Double?
    /// мм.
    public let precipitation: Double?
    /// м/с.
    public let windMax: Double?
    public let sunrise: Date?
    public let sunset: Date?

    public var id: Date { date }

    public init(
        date: Date,
        code: Int?,
        temperatureMin: Double?,
        temperatureMax: Double?,
        precipitation: Double?,
        windMax: Double?,
        sunrise: Date?,
        sunset: Date?
    ) {
        self.date = date
        self.code = code
        self.temperatureMin = temperatureMin
        self.temperatureMax = temperatureMax
        self.precipitation = precipitation
        self.windMax = windMax
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Погода у места: сейчас, давление за 3 дня назад и 3 вперёд, дни прогноза.
public struct PlaceForecast: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    /// Сдвиг местного времени места от UTC — для дней и восхода.
    public let utcOffsetSeconds: Int
    public let current: WeatherSnapshot
    public let pressure: [PressurePoint]
    /// Все дни ответа, включая прошедшие; `upcomingDays` — с сегодняшнего.
    public let days: [ForecastDay]

    public init(fetchedAt: Date, utcOffsetSeconds: Int, current: WeatherSnapshot, pressure: [PressurePoint], days: [ForecastDay]) {
        self.fetchedAt = fetchedAt
        self.utcOffsetSeconds = utcOffsetSeconds
        self.current = current
        self.pressure = pressure
        self.days = days
    }

    /// Изменение давления за сутки до `now` (гПа): по ближайшим почасовым точкам.
    public func pressureChange(before now: Date, hours: Double = 24) -> Double? {
        guard let latest = point(near: now), let earlier = point(near: now.addingTimeInterval(-hours * 3600)),
              latest.time > earlier.time
        else { return nil }
        return latest.pressure - earlier.pressure
    }

    public func pressureTrend(at now: Date) -> PressureTrend? {
        pressureChange(before: now).map(PressureTrend.init(delta:))
    }

    /// Сегодня и дальше — по местному времени места.
    public func upcomingDays(from now: Date, count: Int = 3) -> [ForecastDay] {
        let today = startOfLocalDay(now)
        return Array(days.filter { $0.date >= today }.prefix(count))
    }

    /// Можно ли ещё показывать без обновления.
    public func isFresh(at now: Date, maxAge: TimeInterval = 30 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge
    }

    private func point(near date: Date) -> PressurePoint? {
        // Не дальше полутора часов: на краях ряда сравнивать не с чем.
        pressure
            .min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
            .flatMap { abs($0.time.timeIntervalSince(date)) <= 90 * 60 ? $0 : nil }
    }

    private func startOfLocalDay(_ date: Date) -> Date {
        let local = date.timeIntervalSince1970 + Double(utcOffsetSeconds)
        let day = (local / 86_400).rounded(.down) * 86_400
        return Date(timeIntervalSince1970: day - Double(utcOffsetSeconds))
    }
}

// MARK: - Open-Meteo

/// Запрос погоды к Open-Meteo: координаты округлены до 0,01° (≈1 км) — точнее для погоды не нужно,
/// а точку места сервис не узнаёт; данных аккаунта в запросе нет.
public enum OpenMeteo {
    public static let attributionURL = URL(string: "https://open-meteo.com/")!

    public static func roundedCoordinate(_ point: GeoPoint) -> GeoPoint {
        GeoPoint(
            latitude: (point.latitude * 100).rounded() / 100,
            longitude: (point.longitude * 100).rounded() / 100
        )
    }

    public static func forecastURL(for point: GeoPoint) -> URL {
        let rounded = roundedCoordinate(point)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", rounded.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", rounded.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,surface_pressure"),
            URLQueryItem(name: "hourly", value: "surface_pressure"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max,sunrise,sunset"),
            URLQueryItem(name: "past_days", value: "3"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    /// Ответ Open-Meteo (`timeformat=unixtime`) → прогноз места.
    public static func forecast(from data: Data, fetchedAt: Date) throws -> PlaceForecast {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let current = WeatherSnapshot(
            temperature: response.current?.temperature,
            windSpeed: response.current?.windSpeed,
            windGusts: response.current?.windGusts,
            windDirection: response.current?.windDirection,
            pressure: response.current?.pressure,
            code: response.current?.code
        )
        var pressure: [PressurePoint] = []
        if let hourly = response.hourly {
            for (index, time) in hourly.time.enumerated() where index < hourly.pressure.count {
                if let value = hourly.pressure[index] {
                    pressure.append(PressurePoint(time: Date(timeIntervalSince1970: time), pressure: value))
                }
            }
        }
        var days: [ForecastDay] = []
        if let daily = response.daily {
            for (index, time) in daily.time.enumerated() {
                days.append(ForecastDay(
                    date: Date(timeIntervalSince1970: time),
                    code: daily.code?.value(at: index),
                    temperatureMin: daily.temperatureMin?.value(at: index),
                    temperatureMax: daily.temperatureMax?.value(at: index),
                    precipitation: daily.precipitation?.value(at: index),
                    windMax: daily.windMax?.value(at: index),
                    sunrise: daily.sunrise?.value(at: index).map(Date.init(timeIntervalSince1970:)),
                    sunset: daily.sunset?.value(at: index).map(Date.init(timeIntervalSince1970:))
                ))
            }
        }
        return PlaceForecast(
            fetchedAt: fetchedAt,
            utcOffsetSeconds: response.utcOffsetSeconds ?? 0,
            current: current,
            pressure: pressure,
            days: days
        )
    }

    struct Response: Decodable {
        let utcOffsetSeconds: Int?
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?

        enum CodingKeys: String, CodingKey {
            case utcOffsetSeconds = "utc_offset_seconds"
            case current, hourly, daily
        }
    }

    struct Current: Decodable {
        let temperature: Double?
        let code: Int?
        let windSpeed: Double?
        let windDirection: Double?
        let windGusts: Double?
        let pressure: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case code = "weather_code"
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case windGusts = "wind_gusts_10m"
            case pressure = "surface_pressure"
        }
    }

    struct Hourly: Decodable {
        let time: [Double]
        let pressure: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case pressure = "surface_pressure"
        }
    }

    struct Daily: Decodable {
        let time: [Double]
        let code: [Int?]?
        let temperatureMax: [Double?]?
        let temperatureMin: [Double?]?
        let precipitation: [Double?]?
        let windMax: [Double?]?
        let sunrise: [Double?]?
        let sunset: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case code = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitation = "precipitation_sum"
            case windMax = "wind_speed_10m_max"
            case sunrise, sunset
        }
    }
}

private extension Array {
    func value<T>(at index: Int) -> T? where Element == T? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Единицы

public enum WeatherUnits {
    /// гПа → мм рт. ст.
    public static func millimetersOfMercury(_ hectopascals: Double) -> Int {
        Int((hectopascals * 0.750_062).rounded())
    }

    /// Восемь румбов: 0 — север, 1 — северо-восток … 7 — северо-запад.
    public static func compassSector(_ degrees: Double) -> Int {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return Int((normalized / 45).rounded()) % 8
    }

    public static let compassKeys = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
}
