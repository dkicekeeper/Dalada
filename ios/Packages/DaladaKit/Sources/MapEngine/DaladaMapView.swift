import CoreLocation
import DaladaCore
import MapLibre
import SwiftUI
import UIKit

/// Место для отрисовки на карте.
public struct MapPlace: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Показанная точка (у чужих приблизительных мест — смещённый центр круга).
    public let coordinate: GeoPoint
    public let isOwn: Bool
    /// Радиус круга для приблизительного места; `nil` — точное место.
    public let approximateRadiusM: Int?
    /// Тип места — значок при крупном масштабе; `nil` — всегда точка (например, центр зоны приватности).
    public let type: PlaceType?
    /// Подпись под значком при крупном масштабе.
    public let name: String?

    public init(
        id: UUID,
        coordinate: GeoPoint,
        isOwn: Bool,
        approximateRadiusM: Int?,
        type: PlaceType? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.isOwn = isOwn
        self.approximateRadiusM = approximateRadiusM
        self.type = type
        self.name = name
    }
}

/// Зона на карте: многоугольники (внешний контур и отверстия) и вид — состояние запрета для зон
/// правил, нацпарк, заповедник или погранзона для слоёв карты.
public struct MapRuleArea: Hashable, Sendable, Identifiable {
    public enum State: String, Hashable, Sendable, CaseIterable {
        /// Запрет действует.
        case active
        /// Скоро начнётся.
        case soon
        /// Запрета сейчас нет.
        case none
        /// Национальный парк.
        case park
        /// Заповедник.
        case reserve
        /// Пограничная полоса (вход по пропуску).
        case borderStrip
        /// Пограничная зона.
        case borderZone
    }

    public let id: String
    public let polygons: [[[GeoPoint]]]
    public let state: State

    public init(id: String, polygons: [[[GeoPoint]]], state: State) {
        self.id = id
        self.polygons = polygons
        self.state = state
    }
}

/// Как ведёт себя камера карты.
public enum MapCameraMode: Hashable, Sendable {
    /// Пользователь двигает карту сам.
    case free
    /// Карта следует за пользователем (запись поездки).
    case followUser
    /// Показать трек целиком (страница поездки).
    case fitTrack
}

/// Карта Dalada — SwiftUI-обёртка над `MLNMapView`.
///
/// Места рисуются слоями стиля из одного GeoJSON-источника: круги приблизительных мест, точки мест
/// цвета их типа (мелкий масштаб), значки типа с названием (крупный, `MapPlaceIcons.minZoom`) и метка
/// нового места; трек — линией из отдельного источника. Фичи не импортируют MapLibre — только этот
/// модуль.
public struct DaladaMapView: UIViewRepresentable {
    let styleURL: URL
    let initialCenter: GeoPoint
    let initialZoom: Double
    let showsUserLocation: Bool
    let places: [MapPlace]
    let draftPin: GeoPoint?
    /// Отрезки трека: своя поездка — один, чужая — видимые части без скрытых участков.
    let trackSegments: [[GeoPoint]]
    /// Маршрут, по которому человек идёт (следование), — широкой полупрозрачной линией под треком.
    let routeSegments: [[GeoPoint]]
    /// Слой «Мои треки»: прошлые поездки — тонкой линией под маршрутом и треком.
    let historySegments: [[GeoPoint]]
    let cameraMode: MapCameraMode
    /// «Где я»: каждое новое значение — показать пользователя на карте (дальше карта снова свободна).
    let locateRequest: Int
    /// Зоны правил (запреты) — под местами и треком.
    let ruleAreas: [MapRuleArea]
    let onRegionChange: @MainActor (GeoBoundingBox) -> Void
    let onPlaceTap: @MainActor (UUID) -> Void
    let onRuleAreaTap: @MainActor (String) -> Void
    let onLongPress: @MainActor (GeoPoint) -> Void

    public init(
        styleURL: URL,
        initialCenter: GeoPoint = .almaty,
        initialZoom: Double = 8,
        showsUserLocation: Bool = true,
        places: [MapPlace] = [],
        draftPin: GeoPoint? = nil,
        trackSegments: [[GeoPoint]] = [],
        routeSegments: [[GeoPoint]] = [],
        historySegments: [[GeoPoint]] = [],
        cameraMode: MapCameraMode = .free,
        locateRequest: Int = 0,
        ruleAreas: [MapRuleArea] = [],
        onRegionChange: @escaping @MainActor (GeoBoundingBox) -> Void = { _ in },
        onPlaceTap: @escaping @MainActor (UUID) -> Void = { _ in },
        onRuleAreaTap: @escaping @MainActor (String) -> Void = { _ in },
        onLongPress: @escaping @MainActor (GeoPoint) -> Void = { _ in }
    ) {
        self.styleURL = styleURL
        self.initialCenter = initialCenter
        self.initialZoom = initialZoom
        self.showsUserLocation = showsUserLocation
        self.places = places
        self.draftPin = draftPin
        self.trackSegments = trackSegments
        self.routeSegments = routeSegments
        self.historySegments = historySegments
        self.cameraMode = cameraMode
        self.locateRequest = locateRequest
        self.ruleAreas = ruleAreas
        self.onRegionChange = onRegionChange
        self.onPlaceTap = onPlaceTap
        self.onRuleAreaTap = onRuleAreaTap
        self.onLongPress = onLongPress
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: initialCenter.latitude, longitude: initialCenter.longitude),
            zoomLevel: initialZoom,
            animated: false
        )
        // Запрос разрешения на геолокацию MapLibre делает сам; текст — в InfoPlist.xcstrings.
        mapView.showsUserLocation = showsUserLocation
        mapView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        // Одиночный тап срабатывает, только если это не двойной тап (зум).
        for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)
        context.coordinator.mapView = mapView
        return mapView
    }

    public func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render()
        context.coordinator.applyCamera()
        context.coordinator.applyLocate()
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        var parent: DaladaMapView
        weak var mapView: MLNMapView?
        private var source: MLNShapeSource?
        private var trackSource: MLNShapeSource?
        private var routeSource: MLNShapeSource?
        private var renderedRoute: [[GeoPoint]]?
        private var historySource: MLNShapeSource?
        private var renderedHistory: [[GeoPoint]]?
        private var ruleSource: MLNShapeSource?
        private var renderedRuleAreas: [MapRuleArea]?
        private var renderedPlaces: [MapPlace]?
        private var renderedDraft: GeoPoint?
        private var renderedTrack: [[GeoPoint]]?
        private var appliedCamera: MapCameraMode?
        private var appliedLocate: Int
        private var isStyleLoaded = false

        init(parent: DaladaMapView) {
            self.parent = parent
            appliedLocate = parent.locateRequest
        }

        enum Layer {
            static let source = "dalada-places"
            static let areas = "dalada-place-areas"
            static let points = "dalada-place-points"
            /// Точки мест без типа — при любом масштабе.
            static let plainPoints = "dalada-place-plain-points"
            static let icons = "dalada-place-icons"
            static let labels = "dalada-place-labels"
            static let draft = "dalada-draft-pin"
            static let trackSource = "dalada-track"
            static let trackLine = "dalada-track-line"
            static let routeSource = "dalada-route"
            static let routeLine = "dalada-route-line"
            static let historySource = "dalada-history"
            static let historyLine = "dalada-history-line"
            static let ruleSource = "dalada-rules"
            static let ruleFill = "dalada-rules-fill"
            static let ruleLine = "dalada-rules-line"
        }

        /// Обновляет источник мест, если данные изменились. До загрузки стиля — ничего не делает:
        /// отрисуем в `didFinishLoading`.
        func render() {
            if let ruleSource, parent.ruleAreas != renderedRuleAreas {
                renderedRuleAreas = parent.ruleAreas
                ruleSource.shape = MLNShapeCollectionFeature(shapes: Self.ruleFeatures(parent.ruleAreas))
            }
            if let historySource, parent.historySegments != renderedHistory {
                renderedHistory = parent.historySegments
                historySource.shape = Self.trackShape(parent.historySegments)
            }
            if let routeSource, parent.routeSegments != renderedRoute {
                renderedRoute = parent.routeSegments
                routeSource.shape = Self.trackShape(parent.routeSegments)
            }
            if let trackSource, parent.trackSegments != renderedTrack {
                renderedTrack = parent.trackSegments
                trackSource.shape = Self.trackShape(parent.trackSegments)
            }
            guard let source else { return }
            guard parent.places != renderedPlaces || parent.draftPin != renderedDraft else { return }
            renderedPlaces = parent.places
            renderedDraft = parent.draftPin
            source.shape = MLNShapeCollectionFeature(shapes: Self.features(places: parent.places, draft: parent.draftPin))
        }

        /// Режим камеры применяется один раз при смене: дальше пользователь может двигать карту.
        func applyCamera() {
            guard isStyleLoaded, let mapView, parent.cameraMode != appliedCamera else { return }
            switch parent.cameraMode {
            case .free:
                mapView.userTrackingMode = .none
            case .followUser:
                mapView.showsUserLocation = true
                mapView.setUserTrackingMode(.follow, animated: true, completionHandler: nil)
            case .fitTrack:
                let points = parent.trackSegments.flatMap { $0 }
                guard points.count >= 2 else { return }
                let latitudes = points.map(\.latitude)
                let longitudes = points.map(\.longitude)
                let bounds = MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: latitudes.min()!, longitude: longitudes.min()!),
                    ne: CLLocationCoordinate2D(latitude: latitudes.max()!, longitude: longitudes.max()!)
                )
                mapView.setVisibleCoordinateBounds(
                    bounds,
                    edgePadding: UIEdgeInsets(top: 40, left: 32, bottom: 40, right: 32),
                    animated: false,
                    completionHandler: nil
                )
            }
            appliedCamera = parent.cameraMode
        }

        /// «Где я»: к точке пользователя, не мельче 13-го масштаба. Пока точки нет — режим следования:
        /// MapLibre сам подведёт карту, когда она появится, и отпустит, как только карту сдвинут.
        func applyLocate() {
            guard let mapView, parent.locateRequest != appliedLocate else { return }
            appliedLocate = parent.locateRequest
            mapView.showsUserLocation = true
            if let location = mapView.userLocation?.location {
                mapView.setCenter(location.coordinate, zoomLevel: max(mapView.zoomLevel, 13), animated: true)
            } else {
                mapView.setUserTrackingMode(.follow, animated: true, completionHandler: nil)
            }
        }

        static func trackShape(_ segments: [[GeoPoint]]) -> MLNShape? {
            let lines: [MLNPolylineFeature] = segments.compactMap { segment in
                guard segment.count >= 2 else { return nil }
                var coordinates = segment.map(\.clCoordinate)
                return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            }
            switch lines.count {
            case 0: return nil
            case 1: return lines[0]
            default: return MLNMultiPolylineFeature(polylines: lines)
            }
        }

        /// Цвет зоны по виду. Функции MapLibre — только конструкторами (см. MapPlaceIcons.colorExpression).
        static func ruleAreaColor() -> NSExpression {
            let colors: [MapRuleArea.State: UIColor] = [
                .active: .systemRed,
                .soon: .systemOrange,
                .none: .systemGray,
                .park: .systemGreen,
                .reserve: UIColor(red: 0.05, green: 0.45, blue: 0.3, alpha: 1),
                .borderStrip: .systemPurple,
                .borderZone: .systemPurple,
            ]
            return match(colors.mapValues { NSExpression(forConstantValue: $0) }, default: NSExpression(forConstantValue: UIColor.systemGray))
        }

        /// Прозрачность заливки: запрет и погранполоса заметнее, нацпарки и погранзона — фоном.
        static func ruleAreaOpacity() -> NSExpression {
            let opacity: [MapRuleArea.State: Double] = [
                .active: 0.25, .soon: 0.2, .none: 0.08,
                .park: 0.12, .reserve: 0.2, .borderStrip: 0.3, .borderZone: 0.08,
            ]
            return match(opacity.mapValues { NSExpression(forConstantValue: $0) }, default: NSExpression(forConstantValue: 0.08))
        }

        private static func match(_ values: [MapRuleArea.State: NSExpression], default fallback: NSExpression) -> NSExpression {
            var options: [NSExpression: NSExpression] = [:]
            for (state, value) in values {
                options[NSExpression(forConstantValue: state.rawValue)] = value
            }
            return NSExpression(forMLNMatchingKey: NSExpression(forKeyPath: "state"), in: options, default: fallback)
        }

        static func ruleFeatures(_ areas: [MapRuleArea]) -> [MLNShape & MLNFeature] {
            areas.compactMap { area -> (MLNShape & MLNFeature)? in
                let polygons: [MLNPolygon] = area.polygons.compactMap { rings in
                    guard var outer = rings.first?.map(\.clCoordinate), outer.count >= 3 else { return nil }
                    let holes: [MLNPolygon] = rings.dropFirst().compactMap { ring in
                        var coordinates = ring.map(\.clCoordinate)
                        guard coordinates.count >= 3 else { return nil }
                        return MLNPolygon(coordinates: &coordinates, count: UInt(coordinates.count))
                    }
                    return MLNPolygon(coordinates: &outer, count: UInt(outer.count), interiorPolygons: holes)
                }
                guard !polygons.isEmpty else { return nil }
                let feature = MLNMultiPolygonFeature(polygons: polygons)
                feature.attributes = ["id": area.id, "state": area.state.rawValue]
                return feature
            }
        }

        func installLayers(in style: MLNStyle) {
            // Зоны правил — ниже трека и мест.
            let ruleSource = MLNShapeSource(identifier: Layer.ruleSource, shape: nil, options: nil)
            style.addSource(ruleSource)
            let stateColor = Self.ruleAreaColor()
            let ruleFill = MLNFillStyleLayer(identifier: Layer.ruleFill, source: ruleSource)
            ruleFill.fillColor = stateColor
            ruleFill.fillOpacity = Self.ruleAreaOpacity()
            style.addLayer(ruleFill)
            let ruleLine = MLNLineStyleLayer(identifier: Layer.ruleLine, source: ruleSource)
            ruleLine.lineColor = stateColor
            ruleLine.lineWidth = NSExpression(forConstantValue: 1.5)
            ruleLine.lineOpacity = NSExpression(forConstantValue: 0.7)
            style.addLayer(ruleLine)
            self.ruleSource = ruleSource
            renderedRuleAreas = nil

            // Мои прошлые треки — над зонами, под маршрутом и треком.
            let historySource = MLNShapeSource(identifier: Layer.historySource, shape: nil, options: nil)
            style.addSource(historySource)
            style.addLayer(Self.historyLayer(source: historySource))
            self.historySource = historySource
            renderedHistory = nil

            // Маршрут для следования — под треком.
            let routeSource = MLNShapeSource(identifier: Layer.routeSource, shape: nil, options: nil)
            style.addSource(routeSource)
            let routeLine = MLNLineStyleLayer(identifier: Layer.routeLine, source: routeSource)
            routeLine.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            routeLine.lineWidth = NSExpression(forConstantValue: 7)
            routeLine.lineOpacity = NSExpression(forConstantValue: 0.55)
            routeLine.lineCap = NSExpression(forConstantValue: "round")
            routeLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLine)
            self.routeSource = routeSource
            renderedRoute = nil

            // Трек — под точками мест.
            let trackSource = MLNShapeSource(identifier: Layer.trackSource, shape: nil, options: nil)
            style.addSource(trackSource)
            let trackLine = MLNLineStyleLayer(identifier: Layer.trackLine, source: trackSource)
            trackLine.lineColor = NSExpression(forConstantValue: UIColor.systemOrange)
            trackLine.lineWidth = NSExpression(forConstantValue: 4)
            trackLine.lineCap = NSExpression(forConstantValue: "round")
            trackLine.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(trackLine)
            self.trackSource = trackSource
            renderedTrack = nil

            let source = MLNShapeSource(identifier: Layer.source, shape: nil, options: nil)
            style.addSource(source)
            for type in PlaceType.allCases {
                for own in [false, true] {
                    style.setImage(MapPlaceIcons.image(for: type, own: own), forName: MapPlaceIcons.name(type, own: own))
                }
            }
            for layer in Self.placeLayers(source: source) {
                style.addLayer(layer)
            }

            self.source = source
            renderedPlaces = nil
            render()
        }

        /// Линия слоя «Мои треки»: тонкая, полупрозрачная, чтобы десятки поездок не закрывали карту.
        static func historyLayer(source: MLNSource) -> MLNLineStyleLayer {
            let line = MLNLineStyleLayer(identifier: Layer.historyLine, source: source)
            line.lineColor = NSExpression(forConstantValue: UIColor.systemPurple)
            line.lineWidth = NSExpression(
                forMLNInterpolating: NSExpression(forVariable: "zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [8.0: 1.5, 14.0: 3.0])
            )
            line.lineOpacity = NSExpression(forConstantValue: 0.6)
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            return line
        }

        /// Слои мест снизу вверх: круги приблизительных мест, точки (мелкий масштаб), точки без типа,
        /// значки типов, названия, метка нового места. Значки (`MapPlaceIcons`) добавляются в стиль отдельно.
        /// Свойства переводятся в выражения MapLibre сразу — неверное выражение бросает исключение уже
        /// здесь, поэтому функцию проверяет тест MapEngineTests.
        static func placeLayers(source: MLNSource) -> [MLNStyleLayer] {
            let areas = MLNFillStyleLayer(identifier: Layer.areas, source: source)
            areas.predicate = NSPredicate(format: "kind == 'area'")
            areas.fillColor = NSExpression(forConstantValue: UIColor.systemIndigo)
            areas.fillOpacity = NSExpression(forConstantValue: 0.18)
            areas.fillOutlineColor = NSExpression(forConstantValue: UIColor.systemIndigo)

            // Мелкий масштаб: точки цвета типа; свои — с оранжевой обводкой.
            let points = MLNCircleStyleLayer(identifier: Layer.points, source: source)
            points.predicate = NSPredicate(format: "kind == 'place'")
            points.maximumZoomLevel = Float(MapPlaceIcons.minZoom)
            stylePoints(points, color: MapPlaceIcons.colorExpression())

            // Точки без типа (центр зоны приватности) — при любом масштабе.
            let plainPoints = MLNCircleStyleLayer(identifier: Layer.plainPoints, source: source)
            plainPoints.predicate = NSPredicate(format: "kind == 'plain'")
            stylePoints(plainPoints, color: NSExpression(forConstantValue: UIColor.systemIndigo))

            // Крупный масштаб: значок типа (свои — с оранжевой обводкой).
            let icons = MLNSymbolStyleLayer(identifier: Layer.icons, source: source)
            icons.predicate = NSPredicate(format: "kind == 'place'")
            icons.minimumZoomLevel = Float(MapPlaceIcons.minZoom)
            icons.iconImageName = NSExpression(forKeyPath: "icon")
            // Функции MapLibre — только конструкторами, не строкой формата (см. MapPlaceIcons.colorExpression).
            icons.iconScale = NSExpression(
                forMLNInterpolating: NSExpression(forVariable: "zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [MapPlaceIcons.minZoom: 0.75, MapPlaceIcons.minZoom + 3: 1.0])
            )
            icons.iconAllowsOverlap = NSExpression(forConstantValue: true)
            icons.iconIgnoresPlacement = NSExpression(forConstantValue: true)

            // Названия — ещё крупнее; не помещается — не показываем.
            let labels = MLNSymbolStyleLayer(identifier: Layer.labels, source: source)
            labels.predicate = NSPredicate(format: "kind == 'place'")
            labels.minimumZoomLevel = Float(MapPlaceIcons.labelZoom)
            labels.text = NSExpression(forKeyPath: "name")
            labels.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            labels.textFontSize = NSExpression(forConstantValue: 12)
            labels.textColor = NSExpression(forConstantValue: UIColor(white: 0.15, alpha: 1))
            labels.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            labels.textHaloWidth = NSExpression(forConstantValue: 1.5)
            labels.textAnchor = NSExpression(forConstantValue: "top")
            labels.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.3)))
            labels.maximumTextWidth = NSExpression(forConstantValue: 9)

            let draft = MLNCircleStyleLayer(identifier: Layer.draft, source: source)
            draft.predicate = NSPredicate(format: "kind == 'draft'")
            draft.circleRadius = NSExpression(forConstantValue: 9)
            draft.circleColor = NSExpression(forConstantValue: UIColor.systemRed)
            draft.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            draft.circleStrokeWidth = NSExpression(forConstantValue: 3)

            return [areas, points, plainPoints, icons, labels, draft]
        }

        static func stylePoints(_ layer: MLNCircleStyleLayer, color: NSExpression) {
            // Растёт с масштабом: область целиком — 7 pt, к смене на значки (масштаб 10) — почти как значок.
            layer.circleRadius = NSExpression(
                forMLNInterpolating: NSExpression(forVariable: "zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [5.0: 7.0, MapPlaceIcons.minZoom: 10.0])
            )
            layer.circleColor = color
            layer.circleStrokeColor = NSExpression(
                format: "TERNARY(own == YES, %@, %@)",
                UIColor.systemOrange,
                UIColor.white
            )
            layer.circleStrokeWidth = NSExpression(format: "TERNARY(own == YES, 3, 2)")
        }

        static func features(places: [MapPlace], draft: GeoPoint?) -> [MLNShape & MLNFeature] {
            var features: [MLNShape & MLNFeature] = []
            for place in places {
                if let radius = place.approximateRadiusM {
                    var ring = place.coordinate.circle(radiusM: Double(radius)).map(\.clCoordinate)
                    let area = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                    area.attributes = ["kind": "area", "id": place.id.uuidString]
                    features.append(area)
                }
                let point = MLNPointFeature()
                point.coordinate = place.coordinate.clCoordinate
                // «place» — место с типом (точка → значок), «plain» — точка без типа.
                var attributes: [String: Any] = ["kind": "plain", "id": place.id.uuidString, "own": place.isOwn]
                if let type = place.type {
                    attributes["kind"] = "place"
                    attributes["type"] = type.rawValue
                    attributes["icon"] = MapPlaceIcons.name(type, own: place.isOwn)
                    attributes["name"] = place.name ?? ""
                }
                point.attributes = attributes
                features.append(point)
            }
            if let draft {
                let pin = MLNPointFeature()
                pin.coordinate = draft.clCoordinate
                pin.attributes = ["kind": "draft"]
                features.append(pin)
            }
            return features
        }

        // MARK: Жесты

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView = recognizer.view as? MLNMapView else { return }
            let point = recognizer.location(in: mapView)
            let hitArea = CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
            let hits = mapView.visibleFeatures(
                in: hitArea,
                styleLayerIdentifiers: [Layer.icons, Layer.points, Layer.plainPoints, Layer.areas]
            )
            // Точка важнее круга: если попали в обе, открываем точку.
            let hit = hits.first { ($0.attribute(forKey: "kind") as? String) != "area" } ?? hits.first
            if let idString = hit?.attribute(forKey: "id") as? String, let id = UUID(uuidString: idString) {
                parent.onPlaceTap(id)
                return
            }
            // Мимо мест — зона правил под пальцем.
            let ruleHits = mapView.visibleFeatures(at: point, styleLayerIdentifiers: [Layer.ruleFill])
            if let zoneID = ruleHits.first?.attribute(forKey: "id") as? String {
                parent.onRuleAreaTap(zoneID)
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let mapView = recognizer.view as? MLNMapView else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onLongPress(GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        func reportRegion(of mapView: MLNMapView) {
            let bounds = mapView.visibleCoordinateBounds
            parent.onRegionChange(
                GeoBoundingBox(
                    minLongitude: bounds.sw.longitude,
                    minLatitude: bounds.sw.latitude,
                    maxLongitude: bounds.ne.longitude,
                    maxLatitude: bounds.ne.latitude
                )
            )
        }
    }
}

// Протокол MapLibre не помечен @MainActor, но вызывается на главном потоке.
extension DaladaMapView.Coordinator: @preconcurrency MLNMapViewDelegate {
    public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        installLayers(in: style)
        isStyleLoaded = true
        applyCamera()
        reportRegion(of: mapView)
    }

    public func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        reportRegion(of: mapView)
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
