import Testing
@testable import DaladaCore

@Suite("Фильтр мест на карте")
struct MapPlaceFilterTests {
    @Test func everythingByDefault() {
        let filter = MapPlaceFilter()
        #expect(filter.includes(type: .campsite, isOwn: false))
        #expect(filter.includes(type: nil, isOwn: true))
        #expect(!filter.isActive)
    }

    @Test func hidesTypesAndOwners() {
        let filter = MapPlaceFilter(showsOwn: true, showsOthers: false, hiddenTypes: [.base])
        #expect(!filter.includes(type: .spring, isOwn: false), "чужие скрыты")
        #expect(filter.includes(type: .spring, isOwn: true))
        #expect(!filter.includes(type: .base, isOwn: true), "тип скрыт и у своих")
        #expect(filter.includes(type: nil, isOwn: true))
        #expect(filter.isActive)
    }

    @Test func storesHiddenTypes() {
        let stored = MapPlaceFilter.storage([.campsite, .base])
        #expect(stored == "base,campsite")
        #expect(MapPlaceFilter.types(from: stored) == [.campsite, .base])
        #expect(MapPlaceFilter.types(from: "base,unknown,") == [.base])
        #expect(MapPlaceFilter.types(from: "").isEmpty)
    }
}
