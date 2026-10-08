import DaladaCore
import DesignComponents
import DesignTokens
import PhotosUI
import SwiftUI

/// Форма улова: вид, вес, длина, количество, фото, способ, приманка, отпущена, скрыть размер.
struct CatchFormView: View {
    /// Промысловая мера в месте улова: вид → см (подсказка, без блокировки).
    let minSizes: [String: Int]
    /// Правка сохранённого улова — фото здесь не меняется.
    let allowsPhoto: Bool
    let onDone: @MainActor (CatchDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var draft: CatchDraft
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var photoFailed = false

    init(
        draft: CatchDraft,
        minSizes: [String: Int] = [:],
        allowsPhoto: Bool = true,
        onDone: @escaping @MainActor (CatchDraft) -> Void
    ) {
        self.minSizes = minSizes
        self.allowsPhoto = allowsPhoto
        self.onDone = onDone
        _draft = State(initialValue: draft)
    }

    /// Промысловая мера выбранного вида здесь, см.
    private var minSize: Int? { minSizes[draft.speciesID] }

    /// Длина меньше промысловой меры.
    private var isUndersized: Bool {
        guard let minSize, let length = draft.lengthCm else { return false }
        return length < Double(minSize)
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "catch.form.title"),
            isSaveDisabled: !draft.isValid || isProcessingPhoto,
            wrapInForm: false,
            onSave: {
                onDone(draft)
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "catch.form.species")) {
                        NavigationPickerRow(
                            title: String(localized: "catch.form.species"),
                            selection: $draft.speciesID,
                            options: speciesStore.species.map {
                                (label: $0.name(for: SpeciesStore.languageCode), value: $0.id)
                            }
                        )
                    }

                    FormSection(footer: minSizeHint) {
                        UniversalRow(title: String(localized: "catch.form.weight")) {
                            numberField("catch.form.weightPlaceholder", value: $draft.weightKg, fractionDigits: 0...3)
                        }
                        Divider().padding(.leading, AppSpacing.lg)
                        UniversalRow(title: String(localized: "catch.form.length")) {
                            numberField("catch.form.lengthPlaceholder", value: $draft.lengthCm, fractionDigits: 0...1)
                        }
                        Divider().padding(.leading, AppSpacing.lg)
                        StepperRow(title: String(localized: "catch.form.count"), value: $draft.count, in: 1...1000)
                    }

                    if isUndersized, let minSize {
                        RecommendationBox(
                            text: String(localized: "rules.catch.undersized \(minSize)"),
                            color: AppColors.warning,
                            icon: "ruler"
                        )
                    }

                    if allowsPhoto {
                        FormSection(header: String(localized: "catch.form.photo")) {
                            photoRow
                        }
                        if photoFailed {
                            InlineStatusText(message: String(localized: "photo.failed"), type: .error)
                        }
                    }

                    FormSection(footer: String(localized: "catch.form.hideSizeFooter")) {
                        MenuPickerRow(
                            title: String(localized: "catch.form.method"),
                            selection: $draft.method,
                            options: methodOptions
                        )
                        Divider().padding(.leading, AppSpacing.lg)
                        FormTextField(text: $draft.bait, placeholder: String(localized: "catch.form.bait"), style: .row)
                        Divider().padding(.leading, AppSpacing.lg)
                        ToggleSettingsRow(title: String(localized: "catch.form.released"), config: .standard, isOn: $draft.released)
                        Divider().padding(.leading, AppSpacing.lg)
                        ToggleSettingsRow(title: String(localized: "catch.form.hideSize"), config: .standard, isOn: $draft.hideSize)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
        .task { await speciesStore.loadIfNeeded() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    /// Подсказка о промысловой мере под весом и длиной, пока улов не меньше неё.
    private var minSizeHint: String? {
        guard let minSize, !isUndersized else { return nil }
        return String(localized: "rules.catch.minSizeHint \(minSize)")
    }

    /// Способ ловли: «не указан» и все способы.
    private var methodOptions: [(label: String, value: FishingMethod?)] {
        [(label: String(localized: "common.notSpecified"), value: nil)]
            + FishingMethod.allCases.map { (label: String(localized: String.LocalizationValue($0.titleKey)), value: Optional($0)) }
    }

    /// Фото улова: само фото с кнопкой удаления, плитка-скелетон, пока фото сжимается, или выбор фото.
    @ViewBuilder
    private var photoRow: some View {
        if let photo = draft.photo {
            UniversalRow(config: .standard) {
                PhotoDraftThumbnail(photo: photo)
            } trailing: {
                DSButton(String(localized: "photo.remove"), appearance: .flat, role: .destructive) {
                    draft.photo = nil
                }
            }
        } else if isProcessingPhoto {
            UniversalRow(config: .standard) {
                PhotoTileSkeleton()
            } trailing: {
                EmptyView()
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ActionRowLabel(String(localized: "catch.form.addPhoto"), systemImage: "camera", titleColor: AppColors.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Число в строке формы, справа, как `FormTextField(.inline)`: у DesignKit нет поля с форматом
    /// числа, поэтому здесь системное поле с тем же шрифтом и выравниванием.
    private func numberField(
        _ placeholder: LocalizedStringKey,
        value: Binding<Double?>,
        fractionDigits: ClosedRange<Int>
    ) -> some View {
        TextField(placeholder, value: value, format: .number.precision(.fractionLength(fractionDigits)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        pickerItem = nil
        isProcessingPhoto = true
        photoFailed = false
        defer { isProcessingPhoto = false }
        if let photo = await PhotoCompressor.draft(from: item) {
            draft.photo = photo
        } else {
            photoFailed = true
        }
    }
}
