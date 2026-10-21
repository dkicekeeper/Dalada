import DaladaCore
import DesignComponents
import DesignSupport
import DesignTokens
import SwiftUI

/// Новое место по шагам (`StepTracker` из DesignKit): что за место, описание, кто видит.
/// ✓ сохраняет с любого шага, как только есть название: остальное заполнено по умолчанию.
struct PlaceFormView: View {
    let onSave: @MainActor (PlaceDraft) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlaceDraft
    @State private var step = Step.place
    @State private var isSaving = false
    @State private var saveError: String?

    init(coordinate: GeoPoint, onSave: @escaping @MainActor (PlaceDraft) async -> String?) {
        self.onSave = onSave
        _draft = State(initialValue: PlaceDraft(coordinate: coordinate))
    }

    /// Шаги формы — по порядку.
    enum Step: Int, CaseIterable {
        case place, description, visibility

        var title: String {
            switch self {
            case .place: String(localized: "place.form.step.place")
            case .description: String(localized: "place.form.description")
            case .visibility: String(localized: "place.form.visibility")
            }
        }
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "place.form.title"),
            isSaveDisabled: !draft.isValid,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    StepTracker(steps: Step.allCases.map(\.title), current: step.rawValue)

                    Group {
                        switch step {
                        case .place: placeStep
                        case .description: descriptionStep
                        case .visibility: visibilityStep
                        }
                    }
                    .id(step)
                    .transition(.riseIn)

                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }

                    stepButtons
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .animation(AppAnimation.smooth, value: step)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var placeStep: some View {
        VStack(spacing: AppSpacing.lg) {
            FormSection {
                FormTextField(text: $draft.name, placeholder: String(localized: "place.form.name"), style: .row)
                UniversalRow(
                    String(localized: "place.form.type"),
                    accessory: .menu($draft.type, options: PlaceType.allCases.map {
                        (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                    })
                )
            }

            FormSection {
                UniversalRow(title: String(localized: "place.form.coordinates")) {
                    Text(verbatim: String(format: "%.5f, %.5f", draft.coordinate.latitude, draft.coordinate.longitude))
                        .font(AppTypography.body)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var descriptionStep: some View {
        FormSection(header: String(localized: "place.form.description")) {
            FormTextField(
                text: $draft.description,
                placeholder: String(localized: "place.form.descriptionPlaceholder"),
                style: .rowMultiline(min: 3, max: 8)
            )
        }
    }

    private var visibilityStep: some View {
        FormSection(
            header: String(localized: "place.form.visibility"),
            footer: Self.visibilityFooter(draft.visibility, approximate: draft.effectiveApproximate)
        ) {
            SegmentedPicker(
                title: String(localized: "place.form.visibility"),
                selection: $draft.visibility,
                options: DaladaCore.Visibility.allCases.map {
                    (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                }
            )
            .padding(.vertical, AppSpacing.md)
            UniversalRow(
                String(localized: "place.form.approximate"),
                accessory: .toggle($draft.isApproximate)
            )
            .disabled(draft.visibility == .private)
        }
    }

    /// «Назад» и «Далее»; на последнем шаге вместо «Далее» — «Сохранить».
    private var stepButtons: some View {
        HStack(spacing: AppSpacing.md) {
            if let previous = Step(rawValue: step.rawValue - 1) {
                DSButton(String(localized: "common.back"), appearance: .secondary, fullWidth: true) {
                    step = previous
                }
            }
            if let next = Step(rawValue: step.rawValue + 1) {
                DSButton(String(localized: "intro.next"), fullWidth: true, isDisabled: !draft.isValid) {
                    step = next
                }
            } else {
                DSButton(
                    String(localized: "common.save"),
                    fullWidth: true,
                    isLoading: isSaving,
                    isDisabled: !draft.isValid
                ) {
                    Task { await save() }
                }
            }
        }
    }

    /// Кто увидит место и как — под выбором видимости (новое место и правка своего).
    static func visibilityFooter(_ visibility: DaladaCore.Visibility, approximate: Bool) -> String {
        switch (visibility, approximate) {
        case (.private, _):
            String(localized: "place.form.footer.private")
        case (.friends, false):
            String(localized: "place.form.footer.friends")
        case (.friends, true):
            String(localized: "place.form.footer.friendsApproximate")
        case (.closeFriends, false):
            String(localized: "place.form.footer.closeFriends")
        case (.closeFriends, true):
            String(localized: "place.form.footer.closeFriendsApproximate")
        case (.public, false):
            String(localized: "place.form.footer.public")
        case (.public, true):
            String(localized: "place.form.footer.publicApproximate")
        }
    }

    private func save() async {
        isSaving = true
        saveError = await onSave(draft)
        isSaving = false
        HapticManager.play(saveError == nil ? .confirm : .fail)
        // При успехе лист закрывает модель (сбрасывает запрос на новое место).
    }
}
