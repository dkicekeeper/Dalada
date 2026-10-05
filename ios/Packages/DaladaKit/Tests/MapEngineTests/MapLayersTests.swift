import DaladaCore
import MapLibre
import Testing
import UIKit
@testable import MapEngine

/// Слои и выражения карты собираются без исключений MapLibre. Неразбираемое выражение бросает
/// исключение при загрузке стиля и роняет приложение: сборка 124 падала при открытии вкладки «Карта»,
/// потому что на iOS 26 `NSExpression(format:)` не принимает функции MapLibre (`MGL_MATCH`, `MLN_MATCH`).
/// Этот тест ловит такое до TestFlight.
@MainActor
@Suite("Слои карты")
struct MapLayersTests {
    @Test func placeLayersBuild() {
        let source = MLNShapeSource(identifier: "test-places", shape: nil, options: nil)
        let layers = DaladaMapView.Coordinator.placeLayers(source: source)
        #expect(layers.map(\.identifier) == [
            "dalada-place-areas", "dalada-place-points", "dalada-place-plain-points",
            "dalada-place-icons", "dalada-place-labels", "dalada-draft-pin",
        ])
    }

    @Test func colorExpressionCoversEveryType() {
        // Выражение переводится в стиль при присваивании слою; ошибка — исключение и падение теста.
        let source = MLNShapeSource(identifier: "test-color", shape: nil, options: nil)
        let layer = MLNCircleStyleLayer(identifier: "test-color", source: source)
        layer.circleColor = MapPlaceIcons.colorExpression()
        #expect(layer.identifier == "test-color")
    }

    @Test func zoneExpressionsCoverEveryKind() {
        let source = MLNShapeSource(identifier: "test-zones", shape: nil, options: nil)
        let layer = MLNFillStyleLayer(identifier: "test-zones", source: source)
        layer.fillColor = DaladaMapView.Coordinator.ruleAreaColor()
        layer.fillOpacity = DaladaMapView.Coordinator.ruleAreaOpacity()
        let areas = MapRuleArea.State.allCases.map { state in
            MapRuleArea(id: state.rawValue, polygons: [[[.almaty, GeoPoint(latitude: 43.3, longitude: 76.9), GeoPoint(latitude: 43.3, longitude: 77.0)]]], state: state)
        }
        let features = DaladaMapView.Coordinator.ruleFeatures(areas)
        #expect(features.compactMap { $0.attribute(forKey: "state") as? String } == MapRuleArea.State.allCases.map(\.rawValue))
    }

    @Test func iconsForEveryType() {
        for type in PlaceType.allCases {
            for own in [false, true] {
                let image = MapPlaceIcons.image(for: type, own: own)
                #expect(image.size.width > 20 && image.size.height > 20, "\(type) own=\(own)")
            }
        }
        #expect(Set(PlaceType.allCases.map { MapPlaceIcons.name($0, own: false) }).count == PlaceType.allCases.count)
    }

    @Test func featuresMarkTypedAndPlainPlaces() {
        let typed = MapPlace(
            id: UUID(), coordinate: .almaty, isOwn: true, approximateRadiusM: nil, type: .spring, name: "Родник"
        )
        let plain = MapPlace(id: UUID(), coordinate: .almaty, isOwn: false, approximateRadiusM: 500)
        let features = DaladaMapView.Coordinator.features(places: [typed, plain], draft: nil)
        let kinds = features.compactMap { $0.attribute(forKey: "kind") as? String }
        #expect(kinds == ["place", "area", "plain"])
        #expect(features[0].attribute(forKey: "icon") as? String == "dalada-place-spring-own")
    }
}
