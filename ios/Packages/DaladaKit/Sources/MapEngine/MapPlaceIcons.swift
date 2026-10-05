import DaladaCore
import Foundation
import UIKit

/// Значки мест на карте: круг цвета типа с белым символом типа; у своих мест — оранжевая обводка.
/// Рисуются из SF Symbols при загрузке стиля, поэтому работают и без сети.
enum MapPlaceIcons {
    /// С этого масштаба вместо точек — значки (≈ район города).
    static let minZoom = 10.0
    /// С этого масштаба под значками — названия.
    static let labelZoom = 12.0

    /// Диаметр круга значка, pt.
    private static let diameter: CGFloat = 30

    static func name(_ type: PlaceType, own: Bool) -> String {
        "dalada-place-\(type.rawValue)" + (own ? "-own" : "")
    }

    static func color(for type: PlaceType) -> UIColor {
        switch type {
        case .fishingSpot: .systemBlue
        case .waterBody: .systemTeal
        case .campsite: .systemGreen
        case .paidPond: .systemIndigo
        case .base: .systemBrown
        case .parking: .systemGray
        case .spring: .systemCyan
        case .tackleShop: .systemPurple
        case .landmark: .systemPink
        }
    }

    /// Цвет точки по атрибуту `type` фичи. В MapLibre 6 функция — `MLN_MATCH` (`MGL_MATCH` из Mapbox
    /// бросает исключение при разборе — так падала сборка 124).
    static func colorExpression() -> NSExpression {
        var format = "MLN_MATCH(type"
        var arguments: [Any] = []
        for type in PlaceType.allCases {
            format += ", %@, %@"
            arguments.append(type.rawValue)
            arguments.append(color(for: type))
        }
        format += ", %@)"
        arguments.append(UIColor.systemIndigo)
        return NSExpression(format: format, argumentArray: arguments)
    }

    /// Круг с символом типа, тенью и обводкой (белой; у своих мест — оранжевой).
    static func image(for type: PlaceType, own: Bool) -> UIImage {
        let shadow: CGFloat = 2
        let size = CGSize(width: diameter + shadow * 2, height: diameter + shadow * 2)
        let circle = CGRect(x: shadow, y: shadow, width: diameter, height: diameter)
        let stroke: CGFloat = own ? 3 : 2
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: diameter * 0.46, weight: .semibold)
        let symbol = UIImage(systemName: type.systemImage, withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 0.5), blur: shadow, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            (own ? UIColor.systemOrange : UIColor.white).setFill()
            cg.fillEllipse(in: circle)
            cg.restoreGState()

            color(for: type).setFill()
            cg.fillEllipse(in: circle.insetBy(dx: stroke, dy: stroke))

            if let symbol {
                let fitted = symbol.size.fitting(in: circle.insetBy(dx: diameter * 0.22, dy: diameter * 0.22).size)
                let origin = CGPoint(x: circle.midX - fitted.width / 2, y: circle.midY - fitted.height / 2)
                symbol.draw(in: CGRect(origin: origin, size: fitted))
            }
        }
    }
}

private extension CGSize {
    /// Размер, вписанный в `box` с сохранением пропорций.
    func fitting(in box: CGSize) -> CGSize {
        guard width > 0, height > 0 else { return box }
        let scale = min(box.width / width, box.height / height, 1)
        return CGSize(width: width * scale, height: height * scale)
    }
}
