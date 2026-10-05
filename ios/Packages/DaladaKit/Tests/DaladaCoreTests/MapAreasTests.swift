import Foundation
import Testing
@testable import DaladaCore

@Suite("Слои карты: нацпарки и погранзона")
struct MapAreasTests {
    private let kolsaiRow = """
    {"id": "kolsai", "kind": "national_park",
     "name_ru": "Национальный парк «Кольсайские озёра»", "name_kk": "«Көлсай көлдері» ұлттық паркі", "name_en": "Kolsai Lakes National Park",
     "info_ru": "Въезд платный", "info_kk": "Кіру ақылы", "info_en": "Paid entry",
     "fee_person_mrp": 0.2, "fee_car_mrp": 0.7, "fee_fishing_mrp": 0.3,
     "website_url": "https://kolsai-koldery.kz/", "tickets_url": "https://kolsai-koldery.kz/tickets/list",
     "source_title": "Тарифы ГНПП", "source_url": "https://kolsai-koldery.kz/tickets/list",
     "verified_on": "2026-10-05", "sort_order": 30,
     "geom": {"type": "MultiPolygon", "coordinates": [[[[78.2, 42.9], [78.5, 42.9], [78.5, 43.1], [78.2, 43.1], [78.2, 42.9]]]]}}
    """

    private let borderRow = """
    {"id": "border_zone_kg", "kind": "border_zone",
     "name_ru": "Пограничная зона с Кыргызстаном", "name_kk": "", "name_en": "",
     "info_ru": "До 25 км", "info_kk": "", "info_en": "",
     "fee_person_mrp": null, "fee_car_mrp": null, "fee_fishing_mrp": null,
     "website_url": null, "tickets_url": null, "source_title": "Постановление № 356", "source_url": null,
     "verified_on": "2026-10-05", "sort_order": 80,
     "geom": {"type": "MultiPolygon", "coordinates": [[[[78.0, 42.8], [79.0, 42.8], [79.0, 43.2], [78.0, 43.2], [78.0, 42.8]]]]}}
    """

    private func pack() throws -> MapAreasPack {
        let areas = try JSONDecoder().decode([MapArea].self, from: Data("[\(borderRow), \(kolsaiRow)]".utf8))
        return MapAreasPack(areas: areas, mrp: [MRPValue(year: 2026, tenge: 4325), MRPValue(year: 2025, tenge: 3932)])
    }

    @Test func decodesFeesLinksAndGeometry() throws {
        let kolsai = try #require(try pack().area("kolsai"))
        #expect(kolsai.kind == .nationalPark)
        #expect(kolsai.fees == MapArea.Fees(person: 0.2, car: 0.7, fishing: 0.3))
        #expect(kolsai.ticketsURL?.absoluteString == "https://kolsai-koldery.kz/tickets/list")
        #expect(kolsai.name.text(for: "kk") == "«Көлсай көлдері» ұлттық паркі")
        let border = try #require(try pack().area("border_zone_kg"))
        #expect(border.fees.isEmpty)
        #expect(border.name.text(for: "en") == "Пограничная зона с Кыргызстаном")
        #expect(border.kind.isBorder)
    }

    @Test func sortsAndFindsParksAroundAPoint() throws {
        let pack = try pack()
        #expect(pack.areas.map(\.id) == ["kolsai", "border_zone_kg"])
        let lake = GeoPoint(latitude: 42.99, longitude: 78.32)
        // Погранзона — не парк: в карточке места только парки и заповедники.
        #expect(pack.parks(containing: lake).map(\.id) == ["kolsai"])
        #expect(pack.parks(containing: .almaty).isEmpty)
    }

    @Test func convertsMCIToTengeByYear() throws {
        let pack = try pack()
        #expect(pack.mrpTenge(year: 2026) == 4325)
        #expect(pack.mrpTenge(year: 2027) == 4325)
        #expect(pack.mrpTenge(year: 2025) == 3932)
        #expect(pack.tenge(mrp: 0.7, year: 2026) == 3028)
        #expect(pack.tenge(mrp: 0.2, year: 2026) == 865)
    }

    @Test func savedCopyReadsBack() throws {
        let pack = try pack()
        let copy = try JSONDecoder().decode(MapAreasPack.self, from: JSONEncoder().encode(pack))
        #expect(copy == pack)
    }
}
