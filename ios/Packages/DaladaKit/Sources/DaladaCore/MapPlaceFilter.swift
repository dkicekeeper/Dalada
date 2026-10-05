import Foundation

/// Какие места показывать на карте: свои, остальные и типы. Хранится на телефоне одной строкой.
public struct MapPlaceFilter: Equatable, Sendable {
    public var showsOwn: Bool
    public var showsOthers: Bool
    public var hiddenTypes: Set<PlaceType>

    public init(showsOwn: Bool = true, showsOthers: Bool = true, hiddenTypes: Set<PlaceType> = []) {
        self.showsOwn = showsOwn
        self.showsOthers = showsOthers
        self.hiddenTypes = hiddenTypes
    }

    /// Место без типа (центр зоны приватности друга) — по правилу «свои / остальные».
    public func includes(type: PlaceType?, isOwn: Bool) -> Bool {
        guard isOwn ? showsOwn : showsOthers else { return false }
        guard let type else { return true }
        return !hiddenTypes.contains(type)
    }

    /// Фильтр что-то скрывает — показать это на кнопке «Слои».
    public var isActive: Bool { !showsOwn || !showsOthers || !hiddenTypes.isEmpty }

    /// Скрытые типы для `@AppStorage`: «campsite,base».
    public static func storage(_ types: Set<PlaceType>) -> String {
        types.map(\.rawValue).sorted().joined(separator: ",")
    }

    public static func types(from storage: String) -> Set<PlaceType> {
        Set(storage.split(separator: ",").compactMap { PlaceType(rawValue: String($0)) })
    }
}
