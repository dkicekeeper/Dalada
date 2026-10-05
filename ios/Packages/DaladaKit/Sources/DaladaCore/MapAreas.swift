import Foundation

/// Вид слоя карты (`public.map_area_kind`).
public enum MapAreaKind: String, Codable, CaseIterable, Sendable {
    case nationalPark = "national_park"
    case natureReserve = "nature_reserve"
    case borderStrip = "border_strip"
    case borderZone = "border_zone"

    public var titleKey: String { "mapArea.kind.\(rawValue)" }

    /// Слой «Нацпарки» или «Погранзона».
    public var isBorder: Bool { self == .borderStrip || self == .borderZone }
}

/// Нацпарк, заповедник или погранзона — строка `map_areas`: граница, главное о въезде, тарифы в МРП
/// (только опубликованные самим парком), сайт, билеты и первоисточник.
public struct MapArea: Codable, Identifiable, Hashable, Sendable {
    /// Тарифы в МРП; `nil` — не опубликованы на сайте парка.
    public struct Fees: Hashable, Sendable {
        /// С человека в сутки.
        public let person: Double?
        /// За въезд легкового автомобиля.
        public let car: Double?
        /// Любительская рыбалка, с человека в сутки.
        public let fishing: Double?

        public init(person: Double? = nil, car: Double? = nil, fishing: Double? = nil) {
            self.person = person
            self.car = car
            self.fishing = fishing
        }

        public var isEmpty: Bool { person == nil && car == nil && fishing == nil }
    }

    public let id: String
    public let kind: MapAreaKind
    public let name: LocalizedText
    public let info: LocalizedText
    public let fees: Fees
    public let websiteURL: URL?
    public let ticketsURL: URL?
    public let sourceTitle: String
    public let sourceURL: URL?
    /// Дата проверки на сайте парка или в первоисточнике (ГГГГ-ММ-ДД).
    public let verifiedOn: String
    public let polygons: [GeoPolygon]
    public let sortOrder: Int

    public init(
        id: String,
        kind: MapAreaKind,
        name: LocalizedText,
        info: LocalizedText,
        fees: Fees = Fees(),
        websiteURL: URL? = nil,
        ticketsURL: URL? = nil,
        sourceTitle: String,
        sourceURL: URL? = nil,
        verifiedOn: String,
        polygons: [GeoPolygon],
        sortOrder: Int = 100
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.info = info
        self.fees = fees
        self.websiteURL = websiteURL
        self.ticketsURL = ticketsURL
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.verifiedOn = verifiedOn
        self.polygons = polygons
        self.sortOrder = sortOrder
    }

    public func contains(_ point: GeoPoint) -> Bool {
        polygons.contains { polygon in
            guard let b = polygon.bounds,
                  (b.minLat...b.maxLat).contains(point.latitude),
                  (b.minLon...b.maxLon).contains(point.longitude)
            else { return false }
            return polygon.contains(point)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, geom
        case nameRU = "name_ru", nameKK = "name_kk", nameEN = "name_en"
        case infoRU = "info_ru", infoKK = "info_kk", infoEN = "info_en"
        case feePerson = "fee_person_mrp", feeCar = "fee_car_mrp", feeFishing = "fee_fishing_mrp"
        case websiteURL = "website_url", ticketsURL = "tickets_url"
        case sourceTitle = "source_title", sourceURL = "source_url"
        case verifiedOn = "verified_on"
        case sortOrder = "sort_order"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(MapAreaKind.self, forKey: .kind)
        name = LocalizedText(
            ru: try c.decode(String.self, forKey: .nameRU),
            kk: try c.decodeIfPresent(String.self, forKey: .nameKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .nameEN) ?? ""
        )
        info = LocalizedText(
            ru: try c.decode(String.self, forKey: .infoRU),
            kk: try c.decodeIfPresent(String.self, forKey: .infoKK) ?? "",
            en: try c.decodeIfPresent(String.self, forKey: .infoEN) ?? ""
        )
        fees = Fees(
            person: try c.decodeIfPresent(Double.self, forKey: .feePerson),
            car: try c.decodeIfPresent(Double.self, forKey: .feeCar),
            fishing: try c.decodeIfPresent(Double.self, forKey: .feeFishing)
        )
        websiteURL = try c.decodeIfPresent(String.self, forKey: .websiteURL).flatMap(URL.init(string:))
        ticketsURL = try c.decodeIfPresent(String.self, forKey: .ticketsURL).flatMap(URL.init(string:))
        sourceTitle = try c.decode(String.self, forKey: .sourceTitle)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL).flatMap(URL.init(string:))
        verifiedOn = try c.decode(String.self, forKey: .verifiedOn)
        let geometry = try? c.decodeIfPresent(RuleZone.MultiPolygon.self, forKey: .geom)
        polygons = (geometry?.coordinates ?? []).map { polygon in
            GeoPolygon(rings: polygon.map { ring in
                ring.compactMap { position in
                    position.count >= 2 ? GeoPoint(latitude: position[1], longitude: position[0]) : nil
                }
            })
        }
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 100
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name.ru, forKey: .nameRU)
        try c.encode(name.kk, forKey: .nameKK)
        try c.encode(name.en, forKey: .nameEN)
        try c.encode(info.ru, forKey: .infoRU)
        try c.encode(info.kk, forKey: .infoKK)
        try c.encode(info.en, forKey: .infoEN)
        try c.encodeIfPresent(fees.person, forKey: .feePerson)
        try c.encodeIfPresent(fees.car, forKey: .feeCar)
        try c.encodeIfPresent(fees.fishing, forKey: .feeFishing)
        try c.encodeIfPresent(websiteURL?.absoluteString, forKey: .websiteURL)
        try c.encodeIfPresent(ticketsURL?.absoluteString, forKey: .ticketsURL)
        try c.encode(sourceTitle, forKey: .sourceTitle)
        try c.encodeIfPresent(sourceURL?.absoluteString, forKey: .sourceURL)
        try c.encode(verifiedOn, forKey: .verifiedOn)
        let coordinates = polygons.map { polygon in
            polygon.rings.map { ring in ring.map { [$0.longitude, $0.latitude] } }
        }
        try c.encode(polygons.isEmpty ? nil : RuleZone.MultiPolygon(coordinates: coordinates), forKey: .geom)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

/// МРП года — строка `mrp_values`.
public struct MRPValue: Codable, Hashable, Sendable {
    public let year: Int
    public let tenge: Int

    public init(year: Int, tenge: Int) {
        self.year = year
        self.tenge = tenge
    }
}

/// Слои карты и МРП — справочник для всех; хранится на телефоне, работает без сети.
public struct MapAreasPack: Codable, Hashable, Sendable {
    public let areas: [MapArea]
    public let mrp: [MRPValue]

    public init(areas: [MapArea], mrp: [MRPValue]) {
        self.areas = areas.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
        self.mrp = mrp.sorted { $0.year < $1.year }
    }

    public func area(_ id: String) -> MapArea? {
        areas.first { $0.id == id }
    }

    /// Нацпарки и заповедники, в которых точка (для карточки места).
    public func parks(containing point: GeoPoint) -> [MapArea] {
        areas.filter { !$0.kind.isBorder && $0.contains(point) }
    }

    /// МРП на год: этого года или последнего известного до него.
    public func mrpTenge(year: Int) -> Int? {
        mrp.last { $0.year <= year }?.tenge ?? mrp.first?.tenge
    }

    /// Тариф в тенге по МРП года, округлённый до тенге.
    public func tenge(mrp value: Double, year: Int) -> Int? {
        mrpTenge(year: year).map { Int((value * Double($0)).rounded()) }
    }
}
