import DesignComponents
import DesignTokens
import SwiftUI

/// Пустой экран: крупный символ на круге (`HeroSymbol` DesignKit), заголовок, пояснение.
/// Тексты передаются уже локализованными (EmptyState принимает `String`).
public struct PlaceholderScreen: View {
    private let icon: String
    private let title: String
    private let description: String

    public init(icon: String, title: String, description: String) {
        self.icon = icon
        self.title = title
        self.description = description
    }

    public var body: some View {
        EmptyState(title: title, description: description) {
            HeroSymbol(systemImage: icon)
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PlaceholderScreen(icon: "mappin.and.ellipse", title: "Места", description: "Скоро здесь появятся места.")
}
