import Backend
import DaladaCore
import Foundation
import MapEngine
import Observation
import Persistence

/// Правила и запреты в памяти: сначала сохранённая копия (работает без сети), потом свежая с
/// сервера — не чаще раза в час. Передаётся через `.environment`.
@MainActor
@Observable
final class RulesStore {
    private(set) var pack: RulesPack?
    /// Слои карты: нацпарки, заповедник, погранзона (и МРП для тарифов).
    private(set) var areas: MapAreasPack?
    private let backend: BackendClient?
    private let cache: CacheStore?
    private var isLoading = false
    private var refreshedAt: Date?

    init(backend: BackendClient?, cache: CacheStore? = nil) {
        self.backend = backend
        self.cache = cache
    }

    func loadIfNeeded() async {
        if pack == nil, let cached = try? await cache?.load(RulesPack.self, for: .rules), !cached.isEmpty {
            pack = cached
        }
        if areas == nil, let cached = try? await cache?.load(MapAreasPack.self, for: .mapAreas), !cached.areas.isEmpty {
            areas = cached
        }
        guard let backend, !isLoading else { return }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 3600 { return }
        isLoading = true
        defer { isLoading = false }
        async let loadedRules = try? backend.rulesPack()
        async let loadedAreas = try? backend.mapAreasPack()
        if let loaded = await loadedRules, !loaded.isEmpty {
            pack = loaded
            refreshedAt = Date()
            try? await cache?.save(loaded, for: .rules)
        }
        if let loaded = await loadedAreas, !loaded.areas.isEmpty {
            areas = loaded
            try? await cache?.save(loaded, for: .mapAreas)
        }
    }

    /// Префикс id слоёв карты среди зон на карте: нажатие открывает карточку нацпарка или погранзоны.
    nonisolated static let areaPrefix = "area:"

    /// Нацпарки и заповедники и (или) погранзона для карты — под зонами правил: сначала погранзона,
    /// потом парки, чтобы нажатие внутри парка открывало парк.
    func mapLayerAreas(parks: Bool, border: Bool) -> [MapRuleArea] {
        guard let areas, parks || border else { return [] }
        let shown = areas.areas.filter { $0.kind.isBorder ? border : parks }
        return shown
            .sorted { ($0.kind.isBorder ? 0 : 1, $0.sortOrder) < ($1.kind.isBorder ? 0 : 1, $1.sortOrder) }
            .compactMap { area in
                guard !area.polygons.isEmpty else { return nil }
                let state: MapRuleArea.State = switch area.kind {
                case .nationalPark: .park
                case .natureReserve: .reserve
                case .borderStrip: .borderStrip
                case .borderZone: .borderZone
                }
                return MapRuleArea(id: Self.areaPrefix + area.id, polygons: area.polygons.map(\.rings), state: state)
            }
    }

    /// Сегодня по времени Алматы: сроки в приказах — календарные дни.
    nonisolated static var today: CalendarDay {
        CalendarDay(Date(), calendar: almatyCalendar)
    }

    nonisolated static let almatyCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty") ?? .current
        return calendar
    }()

    /// Язык текстов правил: язык интерфейса, иначе русский.
    static var language: String {
        SpeciesStore.languageCode ?? "ru"
    }

    /// Зоны для карты с цветом по состоянию запрета на сегодня.
    func mapAreas(on day: CalendarDay = RulesStore.today) -> [MapRuleArea] {
        guard let pack else { return [] }
        // Области — первыми, то есть под водоёмами: нажатие на водоём открывает его зону. Область
        // видна, только пока запрет идёт или скоро начнётся, иначе вся страна была бы серой.
        let zones = pack.zones.filter { $0.kind == .region } + pack.zones.filter { $0.kind != .region }
        return zones.compactMap { zone in
            guard !zone.polygons.isEmpty else { return nil }
            let ban = pack.banState(ofZone: zone.id, on: day)
            let state: MapRuleArea.State
            if zone.kind == .region {
                switch ban {
                case .active: state = .regionActive
                case .soon: state = .regionSoon
                case .none: return nil
                }
            } else {
                state = switch ban {
                case .active: .active
                case .soon: .soon
                case .none: .none
                }
            }
            return MapRuleArea(id: zone.id, polygons: zone.polygons.map(\.rings), state: state)
        }
    }
}
