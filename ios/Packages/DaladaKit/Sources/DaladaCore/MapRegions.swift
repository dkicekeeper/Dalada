import Foundation

/// Прямоугольник на карте: юго-западный и северо-восточный углы.
public struct GeoBounds: Hashable, Sendable {
    public var southWest: GeoPoint
    public var northEast: GeoPoint

    public init(south: Double, west: Double, north: Double, east: Double) {
        southWest = GeoPoint(latitude: south, longitude: west)
        northEast = GeoPoint(latitude: north, longitude: east)
    }

    public func contains(_ point: GeoPoint) -> Bool {
        (southWest.latitude...northEast.latitude).contains(point.latitude)
            && (southWest.longitude...northEast.longitude).contains(point.longitude)
    }

    public var center: GeoPoint {
        GeoPoint(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }

    public func contains(_ other: GeoBounds) -> Bool {
        other.southWest.latitude >= southWest.latitude && other.southWest.longitude >= southWest.longitude
            && other.northEast.latitude <= northEast.latitude && other.northEast.longitude <= northEast.longitude
    }

    /// Сколько тайлов (256 px, схема XYZ) покрывают прямоугольник на масштабах `zooms`.
    public func tileCount(zooms: ClosedRange<Int>) -> Int {
        zooms.reduce(0) { total, zoom in
            let (x0, y1) = Self.tile(southWest, zoom: zoom)
            let (x1, y0) = Self.tile(northEast, zoom: zoom)
            return total + (x1 - x0 + 1) * (y1 - y0 + 1)
        }
    }

    static func tile(_ point: GeoPoint, zoom: Int) -> (x: Int, y: Int) {
        let n = Double(1 << zoom)
        let lat = point.latitude * .pi / 180
        let x = Int((point.longitude + 180) / 360 * n)
        let y = Int((1 - asinh(tan(lat)) / .pi) / 2 * n)
        return (min(x, Int(n) - 1), min(y, Int(n) - 1))
    }
}

/// Район, который можно скачать заранее и открывать без сети («Карты без сети»).
public struct MapRegion: Identifiable, Hashable, Sendable {
    public let id: String
    public let bounds: GeoBounds
    /// До какого масштаба скачивать: подробно (14 — тропы, грунтовки, мелкие объекты), для очень
    /// больших районов — 13 (крупнее карта растягивает тайлы 13-го масштаба).
    public let maxZoom: Int
    /// Средний размер тайла подложки, байт (замерено по тайлам в бакете: город и горы у Алматы —
    /// ~13 КБ, степь и вода — меньше 1–2 КБ).
    public let averageTileBytes: Int
    /// Рельеф района целиком: тайлы высот и горизонтали, байт (map/region_sizes.py после сборки
    /// рельефа — таблица в итогах workflow Map tiles).
    public let reliefBytes: Int

    /// С какого масштаба скачивать: мельче район целиком виден и так.
    public static let minZoom = 6

    public var titleKey: String { "offlineMaps.region.\(id)" }
    public var zooms: ClosedRange<Int> { Self.minZoom...maxZoom }
    public var tileCount: Int { bounds.tileCount(zooms: zooms) }

    /// Примерный размер: подложка, рельеф и ~2 МБ шрифтов, значков и стиля.
    public var estimatedBytes: Int64 {
        Int64(tileCount) * Int64(averageTileBytes) + Int64(reliefBytes) + 2 * 1024 * 1024
    }
}

public enum MapRegions {
    /// Всё, что есть на своих тайлах: весь Казахстан (map/config.json → bounds, M34).
    public static let coverage = GeoBounds(south: 40.5, west: 46.4, north: 55.5, east: 87.4)

    public static let all: [MapRegion] = [
        MapRegion(id: "almaty_mountains", bounds: GeoBounds(south: 42.95, west: 76.55, north: 43.45, east: 77.75), maxZoom: 14, averageTileBytes: 13_500, reliefBytes: 15_600_000),
        MapRegion(id: "kapshagay", bounds: GeoBounds(south: 43.55, west: 76.95, north: 44.10, east: 78.15), maxZoom: 14, averageTileBytes: 1_300, reliefBytes: 6_400_000),
        MapRegion(id: "ile", bounds: GeoBounds(south: 43.80, west: 76.10, north: 44.90, east: 77.20), maxZoom: 14, averageTileBytes: 700, reliefBytes: 10_500_000),
        MapRegion(id: "charyn_kolsay", bounds: GeoBounds(south: 42.85, west: 78.00, north: 43.60, east: 79.40), maxZoom: 14, averageTileBytes: 1_300, reliefBytes: 21_800_000),
        MapRegion(id: "ile_delta_balkhash", bounds: GeoBounds(south: 44.70, west: 74.40, north: 46.40, east: 77.60), maxZoom: 13, averageTileBytes: 400, reliefBytes: 38_800_000),
        MapRegion(id: "taldykorgan", bounds: GeoBounds(south: 44.75, west: 77.80, north: 45.45, east: 79.00), maxZoom: 14, averageTileBytes: 1_000, reliefBytes: 11_300_000),
        MapRegion(id: "alakol", bounds: GeoBounds(south: 45.60, west: 80.50, north: 46.75, east: 82.30), maxZoom: 14, averageTileBytes: 400, reliefBytes: 19_200_000),
        // Остальной Казахстан (M34). Рельеф — из итогов workflow Map tiles (map/region_sizes.py,
        // 9 октября 2026); подложка — оценка. Алтай целиком (100 МБ рельефа) разделён на Катон-Карагай
        // и Маркаколь, Усть-Каменогорск с Бухтармой (51 МБ) — на два района.
        // Юг
        MapRegion(id: "shymkent_mountains", bounds: GeoBounds(south: 41.90, west: 69.30, north: 42.85, east: 70.90), maxZoom: 14, averageTileBytes: 3_000, reliefBytes: 30_218_444),
        MapRegion(id: "taraz", bounds: GeoBounds(south: 42.70, west: 71.00, north: 43.20, east: 71.80), maxZoom: 14, averageTileBytes: 2_500, reliefBytes: 4_555_860),
        // Запад
        MapRegion(id: "mangystau", bounds: GeoBounds(south: 42.90, west: 50.90, north: 44.80, east: 55.10), maxZoom: 12, averageTileBytes: 500, reliefBytes: 32_707_058),
        MapRegion(id: "atyrau", bounds: GeoBounds(south: 46.85, west: 51.60, north: 47.35, east: 52.40), maxZoom: 14, averageTileBytes: 1_500, reliefBytes: 0),
        MapRegion(id: "uralsk", bounds: GeoBounds(south: 50.95, west: 50.90, north: 51.45, east: 51.90), maxZoom: 14, averageTileBytes: 2_000, reliefBytes: 0),
        // Центр
        MapRegion(id: "astana", bounds: GeoBounds(south: 50.95, west: 71.10, north: 51.40, east: 71.90), maxZoom: 14, averageTileBytes: 9_000, reliefBytes: 0),
        MapRegion(id: "karkaraly", bounds: GeoBounds(south: 49.20, west: 75.15, north: 49.60, east: 75.80), maxZoom: 14, averageTileBytes: 1_500, reliefBytes: 3_530_861),
        MapRegion(id: "balkhash_north", bounds: GeoBounds(south: 46.40, west: 73.40, north: 47.20, east: 76.20), maxZoom: 13, averageTileBytes: 600, reliefBytes: 8_485_610),
        // Север
        MapRegion(id: "burabay_kokshetau", bounds: GeoBounds(south: 52.55, west: 69.25, north: 53.35, east: 70.90), maxZoom: 14, averageTileBytes: 2_000, reliefBytes: 5_771_788),
        MapRegion(id: "bayanaul", bounds: GeoBounds(south: 50.60, west: 75.40, north: 51.00, east: 76.10), maxZoom: 14, averageTileBytes: 1_500, reliefBytes: 3_596_969),
        MapRegion(id: "pavlodar", bounds: GeoBounds(south: 52.05, west: 76.60, north: 52.55, east: 77.40), maxZoom: 14, averageTileBytes: 2_000, reliefBytes: 0),
        MapRegion(id: "petropavl", bounds: GeoBounds(south: 54.55, west: 68.80, north: 55.10, east: 69.80), maxZoom: 14, averageTileBytes: 1_500, reliefBytes: 0),
        // Восток
        MapRegion(id: "oskemen", bounds: GeoBounds(south: 49.55, west: 82.30, north: 50.20, east: 83.60), maxZoom: 14, averageTileBytes: 1_500, reliefBytes: 17_470_400),
        MapRegion(id: "bukhtarma", bounds: GeoBounds(south: 48.80, west: 82.90, north: 49.75, east: 84.50), maxZoom: 13, averageTileBytes: 1_000, reliefBytes: 28_166_873),
        MapRegion(id: "katon_karagay", bounds: GeoBounds(south: 48.95, west: 85.50, north: 49.90, east: 87.10), maxZoom: 13, averageTileBytes: 1_000, reliefBytes: 43_506_985),
        MapRegion(id: "markakol", bounds: GeoBounds(south: 48.55, west: 85.40, north: 48.95, east: 86.20), maxZoom: 14, averageTileBytes: 800, reliefBytes: 8_458_987),
        MapRegion(id: "zaysan", bounds: GeoBounds(south: 47.30, west: 82.70, north: 48.40, east: 85.20), maxZoom: 13, averageTileBytes: 700, reliefBytes: 15_714_648),
    ]

    public static func region(id: String) -> MapRegion? {
        all.first { $0.id == id }
    }

    /// Район для «скачайте заранее»: тот, где человек сейчас (самый маленький из подходящих),
    /// иначе ближайший по центру. Без позиции — Алматы и горы: там живёт большинство.
    public static func suggested(near point: GeoPoint?) -> MapRegion {
        let fallback = all[0]
        guard let point else { return fallback }
        let containing = all.filter { $0.bounds.contains(point) }
        if let smallest = containing.min(by: { $0.tileCount < $1.tileCount }) {
            return smallest
        }
        return all.min { point.distance(to: $0.bounds.center) < point.distance(to: $1.bounds.center) } ?? fallback
    }
}
