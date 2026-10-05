import DaladaCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Погода у места — напрямую из Open-Meteo, без нашего сервера и без данных аккаунта: в запросе только
/// координаты, округлённые до 0,01°. Работает и у гостя.
public struct WeatherClient: Sendable {
    public enum WeatherError: Error {
        case unavailable
    }

    public init() {}

    public func forecast(at point: GeoPoint) async throws -> PlaceForecast {
        let request = URLRequest(url: OpenMeteo.forecastURL(for: point), timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.unavailable
        }
        return try OpenMeteo.forecast(from: data, fetchedAt: Date())
    }
}
