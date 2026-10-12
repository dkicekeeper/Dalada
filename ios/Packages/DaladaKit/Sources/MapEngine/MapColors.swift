import DaladaCore
import DesignTokens
import SwiftUI
import UIKit

/// Цвета карты. Значки, линии и зоны берут глубокие оттенки палитры DesignKit
/// (`AppColors.Palette`, 3.7.0): они одинаковые в светлой и тёмной теме (значок рисуется один раз
/// при загрузке стиля и не перекрашивается), и белый символ на значке читается (контраст от
/// 4,5:1, у системных цветов было до 2,2:1). Зоны запретов — токены статусов DesignKit, как и
/// бейджи правил. Какой тип или слой какого цвета — решает Dalada здесь.
enum MapColors {
    /// Круг значка и точка места по типу.
    static func place(_ type: PlaceType) -> UIColor {
        let hue: AppColors.Palette = switch type {
        case .fishingSpot: .blue
        case .waterBody: .teal
        case .campsite: .green
        case .paidPond: .indigo
        case .base: .ochre
        case .parking: .slate
        case .spring: .cyan
        case .tackleShop: .purple
        case .landmark: .pink
        }
        return hue.uiColor
    }

    /// Точки без типа и области приватности.
    static var area: UIColor { AppColors.Palette.indigo.uiColor }
    /// Обводка своих мест.
    static var own: UIColor { AppColors.Palette.orange.uiColor }
    /// Маршрут для следования.
    static var route: UIColor { AppColors.Palette.blue.uiColor }
    /// Записываемый трек.
    static var track: UIColor { AppColors.Palette.orange.uiColor }
    /// Слой «Мои треки».
    static var history: UIColor { AppColors.Palette.purple.uiColor }
    /// Фото на треке.
    static var photo: UIColor { AppColors.Palette.pink.uiColor }
    /// Метка нового места.
    static var draft: UIColor { AppColors.Palette.red.uiColor }

    /// Заливка зоны по виду: запрет и «скоро» — статусы DesignKit, парки, заповедники и
    /// погранзоны — палитра.
    static func zone(_ state: MapRuleArea.State) -> UIColor {
        switch state {
        case .active, .regionActive: UIColor(AppColors.Status.negative)
        case .soon, .regionSoon: UIColor(AppColors.Status.warning)
        case .none: UIColor(AppColors.Status.neutral)
        case .park: AppColors.Palette.green.uiColor
        case .reserve: AppColors.Palette.emerald.uiColor
        case .borderStrip, .borderZone: AppColors.Palette.purple.uiColor
        }
    }
}
