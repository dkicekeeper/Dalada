import DesignComponents
import DesignTokens
import SwiftUI

// Помощники форм поверх строк DesignKit: то, что нужно нескольким формам Dalada.

/// Ряд чипов внутри карточки `FormSection`: подпись с отступом карточки, чипы прокручиваются
/// от края до края (у `ChipPicker` подпись без отступа). Чекин, правка отчёта, «Информация» места.
struct FormChipRow<Option: Hashable>: View {
    let title: String?
    let picker: ChipPicker<Option>

    init(
        _ title: String? = nil,
        options: [Option],
        selection: Binding<Option?>,
        systemImage: ((Option) -> String?)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.title = title
        self.picker = ChipPicker(options: options, selection: selection, systemImage: systemImage, label: label)
    }

    init(
        _ title: String? = nil,
        options: [Option],
        selection: Binding<Set<Option>>,
        systemImage: ((Option) -> String?)? = nil,
        label: @escaping (Option) -> String
    ) {
        self.title = title
        self.picker = ChipPicker(options: options, selection: selection, systemImage: systemImage, label: label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let title {
                Text(verbatim: title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.lg)
            }
            picker
                .contentMargins(.horizontal, AppSpacing.lg, for: .scrollContent)
        }
    }
}

/// Строка-кнопка «Добавить фото» в карточке формы: значок и подпись акцентом. Метку `PhotosPicker`
/// SwiftUI собирает вне главного актора, а инициализаторы строк DesignKit — на нём; поэтому строка
/// собирается в `body` этого вида, а сам он создаётся где угодно.
struct PickerRowLabel: View {
    let title: String
    let systemImage: String
    let titleColor: Color

    nonisolated init(_ title: String, systemImage: String, titleColor: Color = AppColors.accent) {
        self.title = title
        self.systemImage = systemImage
        self.titleColor = titleColor
    }

    var body: some View {
        UniversalRow(
            leadingIcon: .sfSymbol(systemImage, color: AppColors.accent, size: AppIconSize.lg),
            title: title,
            titleColor: titleColor
        )
        .contentShape(Rectangle())
    }
}
