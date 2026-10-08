import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Форма нового места: название, тип, описание, видимость, «приблизительно».
struct PlaceFormView: View {
    let onSave: @MainActor (PlaceDraft) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlaceDraft
    @State private var isSaving = false
    @State private var saveError: String?

    init(coordinate: GeoPoint, onSave: @escaping @MainActor (PlaceDraft) async -> String?) {
        self.onSave = onSave
        _draft = State(initialValue: PlaceDraft(coordinate: coordinate))
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
                    FormSection {
                        FormTextField(text: $draft.name, placeholder: String(localized: "place.form.name"), style: .row)
                        Divider().padding(.leading, AppSpacing.lg)
                        MenuPickerRow(
                            title: String(localized: "place.form.type"),
                            selection: $draft.type,
                            options: PlaceType.allCases.map {
                                (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                            }
                        )
                    }

                    FormSection(header: String(localized: "place.form.description")) {
                        FormTextField(
                            text: $draft.description,
                            placeholder: String(localized: "place.form.descriptionPlaceholder"),
                            style: .rowMultiline(min: 3, max: 8)
                        )
                    }

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
                        .padding(AppSpacing.md)
                        Divider().padding(.leading, AppSpacing.lg)
                        ToggleSettingsRow(
                            title: String(localized: "place.form.approximate"),
                            config: .standard,
                            isOn: $draft.isApproximate
                        )
                        .disabled(draft.visibility == .private)
                    }

                    FormSection {
                        UniversalRow(title: String(localized: "place.form.coordinates")) {
                            Text(verbatim: String(format: "%.5f, %.5f", draft.coordinate.latitude, draft.coordinate.longitude))
                                .font(AppTypography.body)
                                .monospacedDigit()
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
        .interactiveDismissDisabled(isSaving)
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
        // При успехе лист закрывает модель (сбрасывает запрос на новое место).
    }
}
