import Backend
import DaladaCore
import DesignComponents
import DesignSupport
import DesignTokens
import SwiftUI

// MARK: - Сводка отчётов

/// «За 7 дней: 12 отчётов, клёв в основном хороший».
struct PlaceReportsSummaryView: View {
    let summary: PlaceReportsSummary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "chart.bar.xaxis")
        }
        .font(AppTypography.bodySmall)
        .foregroundStyle(AppColors.textSecondary)
    }

    private var text: String {
        let count = summary.isLowerBound
            ? String(localized: "place.summary.reportsAtLeast \(summary.count)")
            : String(localized: "place.summary.reports \(summary.count)")
        guard let bite = summary.bite else { return count }
        return count + ", " + String(localized: String.LocalizationValue("place.summary.bite.\(bite.rawValue)"))
    }
}

// MARK: - «Информация»

/// Атрибуты места: рыба, способы ловли, подъезд, стоимость, удобства, связь, сезон, особенности.
/// Своё место — «Изменить»; чужое публичное — «Предложить правку» и «Сообщить о проблеме».
struct PlaceInfoSection: View {
    let place: PlaceDetails
    let canEdit: Bool
    let canSuggest: Bool
    /// Мои предложения к месту, которые ещё на проверке.
    let pendingSuggestions: Set<PlaceSuggestionKind>
    let onEdit: () -> Void
    let onSuggest: (PlaceSuggestionKind) -> Void
    /// Во вкладке карточки места заголовок — сам чип.
    var showsHeader = true

    @Environment(SpeciesStore.self) private var speciesStore

    private var info: PlaceAttributes { place.info.normalized }

    var body: some View {
        if !info.isEmpty || canEdit || canSuggest {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if showsHeader {
                    SectionHeader(String(localized: "place.info.title"), systemImage: "info.circle")
                }
                if info.isEmpty {
                    Text(LocalizedStringKey(canEdit ? "place.info.empty.own" : "place.info.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(rows, id: \.titleKey) { row in
                            PlaceInfoRow(row: row)
                        }
                    }
                    .cardContentPadding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                actions
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if canEdit {
            Button(action: onEdit) {
                Label(LocalizedStringKey(info.isEmpty ? "place.info.add" : "place.info.edit"), systemImage: "square.and.pencil")
                    .font(AppTypography.bodySmall)
            }
        } else if canSuggest {
            HStack(spacing: AppSpacing.lg) {
                Button {
                    onSuggest(.edit)
                } label: {
                    Label("place.suggest.edit", systemImage: "square.and.pencil")
                }
                Menu {
                    ForEach(PlaceSuggestionKind.problems) { kind in
                        Button(LocalizedStringKey(kind.titleKey)) { onSuggest(kind) }
                    }
                } label: {
                    Label("place.suggest.problem", systemImage: "exclamationmark.bubble")
                }
            }
            .font(AppTypography.bodySmall)
            if !pendingSuggestions.isEmpty {
                Label("place.suggest.pending", systemImage: "hourglass")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    /// Строки по порядку: у мест для рыбалки сначала рыба и способы ловли.
    private var rows: [PlaceInfoRow.Model] {
        var fishing: [PlaceInfoRow.Model] = []
        if !info.species.isEmpty {
            fishing.append(.init(titleKey: "place.info.species", systemImage: "fish", value: speciesText))
        }
        if !info.methods.isEmpty {
            fishing.append(.init(
                titleKey: "place.info.methods",
                systemImage: "figure.fishing",
                value: Self.titles(PlaceAttributes.Method.allCases.filter { info.methods.contains($0) }, \.titleKey)
            ))
        }
        var other: [PlaceInfoRow.Model] = []
        if !info.access.isEmpty {
            other.append(.init(
                titleKey: "place.info.access",
                systemImage: "car",
                value: Self.titles(PlaceAttributes.Access.allCases.filter { info.access.contains($0) }, \.titleKey)
            ))
        }
        if let fee = feeText {
            other.append(.init(titleKey: "place.info.fee", systemImage: "banknote", value: fee))
        }
        if let contact = info.contact {
            other.append(.init(titleKey: "place.info.contact", systemImage: "phone", value: contact, isSelectable: true))
        }
        if !info.amenities.isEmpty {
            other.append(.init(
                titleKey: "place.info.amenities",
                systemImage: "checklist",
                value: Self.titles(PlaceAttributes.Amenity.allCases.filter { info.amenities.contains($0) }, \.titleKey)
            ))
        }
        if let signal = info.signal {
            other.append(.init(
                titleKey: "place.info.signal",
                systemImage: "antenna.radiowaves.left.and.right",
                value: String(localized: String.LocalizationValue(signal.titleKey))
            ))
        }
        if !info.months.isEmpty {
            other.append(.init(titleKey: "place.info.months", systemImage: "calendar", value: monthsText))
        }
        if let features = info.features {
            other.append(.init(titleKey: "place.info.features", systemImage: "text.alignleft", value: features))
        }
        return place.type.isFishing ? fishing + other : other + fishing
    }

    private var speciesText: String {
        let order = Dictionary(uniqueKeysWithValues: speciesStore.species.map { ($0.id, $0.sortOrder) })
        return info.species
            .sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
            .map { speciesStore.name(for: $0) }
            .joined(separator: ", ")
    }

    private var feeText: String? {
        guard let fee = info.fee else { return nil }
        var parts = [String(localized: String.LocalizationValue(fee.titleKey))]
        if let price = info.priceKZT {
            var priceText = price.formatted(.number) + " ₸"
            if let unit = info.priceUnit {
                priceText += " " + String(localized: String.LocalizationValue(unit.titleKey))
            }
            parts.append(priceText)
        }
        return parts.joined(separator: " · ")
    }

    private var monthsText: String {
        let symbols = PlaceMonths.names
        let text = PlaceAttributes.monthSpans(info.months)
            .map { span in
                span.from == span.to ? symbols[span.from - 1] : symbols[span.from - 1] + "–" + symbols[span.to - 1]
            }
            .joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func titles<T>(_ values: [T], _ key: KeyPath<T, String>) -> String {
        values.map { String(localized: String.LocalizationValue($0[keyPath: key])) }.joined(separator: ", ")
    }
}

/// Строка «Информации»: значок, подпись, значение.
private struct PlaceInfoRow: View {
    struct Model {
        let titleKey: String
        let systemImage: String
        let value: String
        var isSelectable = false
    }

    let row: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Image(systemName: row.systemImage)
                .foregroundStyle(AppColors.accent)
                .frame(width: AppIconSize.md)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(LocalizedStringKey(row.titleKey))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if row.isSelectable {
                    Text(verbatim: row.value)
                        .font(AppTypography.bodySmall)
                        .textSelection(.enabled)
                } else {
                    Text(verbatim: row.value)
                        .font(AppTypography.bodySmall)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Названия месяцев на языке интерфейса (по-русски и по-казахски — со строчной).
enum PlaceMonths {
    static var names: [String] { formatter.standaloneMonthSymbols }

    static var shortNames: [String] {
        formatter.shortStandaloneMonthSymbols.map { $0.trimmingCharacters(in: .punctuationCharacters) }
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppConfig.interfaceLanguage)
        return formatter
    }
}

// MARK: - Поля «Информации» в формах

extension PlaceAttributes.Access: TitledOption {}
extension PlaceAttributes.Fee: TitledOption {}
extension PlaceAttributes.PriceUnit: TitledOption {}
extension PlaceAttributes.Method: TitledOption {}
extension PlaceAttributes.Amenity: TitledOption {}
extension PlaceAttributes.Signal: TitledOption {}

/// Поля атрибутов в форме: своё место и предложение правки. Короткие списки — чипами, рыба —
/// отдельным списком.
struct PlaceAttributesFields: View {
    @Binding var attributes: PlaceAttributes
    let type: PlaceType

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        FormSection(header: String(localized: "place.info.title")) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if type.isFishing {
                    fishing
                }
                FormChipRow(
                    String(localized: "place.info.access"),
                    options: PlaceAttributes.Access.allCases,
                    selection: $attributes.access
                ) { $0.title }
                FormChipRow(
                    String(localized: "place.info.amenities"),
                    options: PlaceAttributes.Amenity.allCases,
                    selection: $attributes.amenities,
                    systemImage: { $0.systemImage }
                ) { $0.title }
                FormChipRow(
                    String(localized: "place.info.signal"),
                    options: PlaceAttributes.Signal.allCases,
                    selection: $attributes.signal
                ) { $0.title }
                FormChipRow(
                    String(localized: "place.info.months"),
                    options: Array(1...12),
                    selection: $attributes.months
                ) { PlaceMonths.shortNames[$0 - 1] }
                if !type.isFishing {
                    fishing
                }
            }
            .padding(.vertical, AppSpacing.md)
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSection(header: String(localized: "place.info.fee")) {
                FormChipRow(options: PlaceAttributes.Fee.allCases, selection: $attributes.fee) { $0.title }
                    .padding(.vertical, AppSpacing.md)
                if attributes.fee == .paid {
                    Divider().padding(.leading, AppSpacing.lg)
                    UniversalRow(config: .standard) {
                        TextField("place.info.price", text: priceText)
                            .keyboardType(.numberPad)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                    } trailing: {
                        Text(verbatim: "₸")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    FormChipRow(options: PlaceAttributes.PriceUnit.allCases, selection: $attributes.priceUnit) { $0.title }
                        .padding(.bottom, AppSpacing.md)
                }
                Divider().padding(.leading, AppSpacing.lg)
                FormTextField(
                    text: text(\.contact),
                    placeholder: String(localized: "place.info.contact.placeholder"),
                    style: .row
                )
                .textContentType(.telephoneNumber)
            }
            if (attributes.contact?.count ?? 0) > PlaceAttributes.contactLimit {
                InlineStatusText(message: String(localized: "place.info.tooLong \(PlaceAttributes.contactLimit)"), type: .error)
            }
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSection(header: String(localized: "place.info.features")) {
                FormTextField(
                    text: text(\.features),
                    placeholder: String(localized: "place.info.features.placeholder"),
                    style: .rowMultiline(min: 2, max: 6)
                )
            }
            if (attributes.features?.count ?? 0) > PlaceAttributes.featuresLimit {
                InlineStatusText(message: String(localized: "place.info.tooLong \(PlaceAttributes.featuresLimit)"), type: .error)
            }
        }
    }

    /// Рыба (списком — видов много) и способы ловли.
    @ViewBuilder
    private var fishing: some View {
        NavigationLink {
            SpeciesSelectList(
                species: speciesStore.species.sorted { $0.sortOrder < $1.sortOrder },
                selection: Binding(
                    get: { Set(attributes.species) },
                    set: { selected in
                        let order = Dictionary(uniqueKeysWithValues: speciesStore.species.map { ($0.id, $0.sortOrder) })
                        attributes.species = selected.sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
                    }
                )
            )
        } label: {
            UniversalRow(title: String(localized: "place.info.species")) {
                HStack(spacing: AppSpacing.sm) {
                    Group {
                        if attributes.species.isEmpty {
                            Text("common.notSpecified")
                        } else {
                            Text(verbatim: "\(attributes.species.count)")
                        }
                    }
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    DisclosureChevron()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        FormChipRow(
            String(localized: "place.info.methods"),
            options: PlaceAttributes.Method.allCases,
            selection: $attributes.methods
        ) { $0.title }
    }

    private var priceText: Binding<String> {
        Binding(
            get: { attributes.priceKZT.map(String.init) ?? "" },
            set: { value in
                let digits = String(value.filter(\.isASCIIDigit).prefix(7))
                attributes.priceKZT = Int(digits)
            }
        )
    }

    private func text(_ keyPath: WritableKeyPath<PlaceAttributes, String?>) -> Binding<String> {
        Binding(
            get: { attributes[keyPath: keyPath] ?? "" },
            set: { attributes[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Виды рыбы места: выбрать несколько.
private struct SpeciesSelectList: View {
    let species: [FishSpecies]
    @Binding var selection: Set<String>

    var body: some View {
        List(species) { item in
            let isSelected = selection.contains(item.id)
            Button {
                if isSelected {
                    selection.remove(item.id)
                } else {
                    selection.insert(item.id)
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    SelectionIndicator(isSelected: isSelected)
                    Text(verbatim: item.name(for: SpeciesStore.languageCode))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .navigationTitle("place.info.species")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Своё место: изменить

/// Изменить своё место: название, тип, описание, «Информация», видимость. Точку пока не двигаем.
struct PlaceEditView: View {
    let placeID: UUID
    let environment: AppEnvironment
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: OwnPlaceDraft?
    @State private var original: OwnPlaceDraft?
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        EditSheetContainer(
            title: String(localized: "place.edit.title"),
            isSaveDisabled: draft == nil || draft == original || draft?.isValid != true,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            Group {
                if let draft = Binding($draft) {
                    form(draft)
                        .transition(.skeletonReveal)
                } else if let loadError {
                    EmptyState(
                        icon: "wifi.slash",
                        title: String(localized: "place.card.failed"),
                        description: loadError,
                        actionTitle: String(localized: "common.retry"),
                        action: { Task { await load() } },
                        style: .error
                    )
                } else {
                    // Место грузится: скелетоны карточек формы.
                    ScrollView {
                        VStack(spacing: AppSpacing.lg) {
                            FormSection {
                                UniversalRowSkeleton(iconStyle: nil)
                                Divider().padding(.leading, AppSpacing.lg)
                                UniversalRowSkeleton(iconStyle: nil, trailing: .value)
                            }
                            FormSection {
                                UniversalRowSkeleton(iconStyle: nil, showsSubtitle: true)
                            }
                            FormSection {
                                UniversalRowSkeleton(iconStyle: nil, trailing: .capsule)
                                Divider().padding(.leading, AppSpacing.lg)
                                UniversalRowSkeleton(iconStyle: nil, trailing: .toggle)
                            }
                        }
                        .screenPadding()
                        .padding(.vertical, AppSpacing.md)
                    }
                    .scrollDisabled(true)
                    .transition(.opacity)
                }
            }
            // Место загрузилось — форма проявляется на месте скелетонов.
            .animation(AppAnimation.smooth, value: draft == nil)
        }
        .interactiveDismissDisabled(isSaving || (draft != nil && draft != original))
        .task { await load() }
    }

    private func form(_ draft: Binding<OwnPlaceDraft>) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                FormSection {
                    FormTextField(text: draft.fields.name, placeholder: String(localized: "place.form.name"), style: .row)
                    Divider().padding(.leading, AppSpacing.lg)
                    MenuPickerRow(
                        title: String(localized: "place.form.type"),
                        selection: draft.fields.type,
                        options: PlaceType.allCases.map {
                            (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                        }
                    )
                }

                FormSection(header: String(localized: "place.form.description")) {
                    FormTextField(
                        text: draft.fields.description,
                        placeholder: String(localized: "place.form.descriptionPlaceholder"),
                        style: .rowMultiline(min: 3, max: 8)
                    )
                }

                PlaceAttributesFields(attributes: draft.fields.attributes, type: draft.wrappedValue.fields.type)

                FormSection(
                    header: String(localized: "place.form.visibility"),
                    footer: PlaceFormView.visibilityFooter(
                        draft.wrappedValue.visibility,
                        approximate: draft.wrappedValue.effectiveApproximate
                    )
                ) {
                    SegmentedPicker(
                        title: String(localized: "place.form.visibility"),
                        selection: draft.visibility,
                        options: DaladaCore.Visibility.allCases.map {
                            (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                        }
                    )
                    .padding(AppSpacing.md)
                    Divider().padding(.leading, AppSpacing.lg)
                    ToggleSettingsRow(
                        title: String(localized: "place.form.approximate"),
                        config: .standard,
                        isOn: draft.isApproximate
                    )
                    .disabled(draft.wrappedValue.visibility == .private)
                }

                if let saveError {
                    InlineStatusText(message: saveError, type: .error)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func load() async {
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        loadError = nil
        do {
            if let loaded = try await backend.ownPlace(id: placeID) {
                original = loaded
                draft = loaded
            } else {
                loadError = String(localized: "place.card.notFound.description")
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let draft, let backend = environment.backend else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.updatePlace(id: placeID, draft)
            HapticManager.play(.confirm)
            onSaved()
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
            HapticManager.play(.fail)
        }
    }
}

// MARK: - Чужое место: предложить правку, сообщить о проблеме

/// Предложение к чужому публичному месту: правка полей или проблема (не та точка, закрыто, не
/// существует, дубль, опасно). Разбирает редакция.
struct PlaceSuggestView: View {
    let place: PlaceDetails
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var kind: PlaceSuggestionKind
    @State private var draft: PlaceEditDraft
    @State private var note = ""
    @State private var isSending = false
    @State private var isSent = false
    @State private var sendError: String?

    private let original: PlaceEditDraft

    init(place: PlaceDetails, kind: PlaceSuggestionKind, environment: AppEnvironment) {
        self.place = place
        self.environment = environment
        let original = PlaceEditDraft(place: place)
        self.original = original
        _kind = State(initialValue: kind)
        _draft = State(initialValue: original)
    }

    private var changes: PlaceChanges { draft.changes(from: original) }

    private var canSend: Bool {
        guard note.count <= PlaceEditDraft.noteLimit else { return false }
        return kind == .edit ? !changes.isEmpty && draft.isValid : true
    }

    var body: some View {
        if isSent {
            NavigationStack {
                EmptyState(
                    icon: "checkmark.circle.fill",
                    title: String(localized: "place.suggest.sent"),
                    description: String(localized: "place.suggest.sentDetail")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(LocalizedStringKey(kind == .edit ? "place.suggest.edit" : "place.suggest.problem"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                }
            }
        } else {
            EditSheetContainer(
                title: String(localized: String.LocalizationValue(kind == .edit ? "place.suggest.edit" : "place.suggest.problem")),
                saveTitle: String(localized: "place.suggest.send"),
                isSaveDisabled: !canSend,
                isSaving: isSending,
                wrapInForm: false,
                onSave: { Task { await send() } },
                onCancel: { dismiss() }
            ) {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        if kind == .edit {
                            editFields
                        } else {
                            problemKinds
                        }

                        FormSection(
                            header: String(localized: "place.suggest.note"),
                            footer: String(localized: "place.suggest.footer")
                        ) {
                            FormTextField(
                                text: $note,
                                placeholder: String(localized: "place.suggest.notePlaceholder"),
                                style: .rowMultiline(min: 2, max: 6)
                            )
                        }

                        if let sendError {
                            InlineStatusText(message: sendError, type: .error)
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .interactiveDismissDisabled(isSending)
        }
    }

    @ViewBuilder
    private var editFields: some View {
        FormSection(footer: String(localized: "place.suggest.editHint")) {
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

        PlaceAttributesFields(attributes: $draft.attributes, type: draft.type)
    }

    private var problemKinds: some View {
        FormSection(header: String(localized: "place.suggest.problem.what")) {
            let options = PlaceSuggestionKind.problems
            ForEach(options) { option in
                CheckmarkRow(
                    String(localized: String.LocalizationValue(option.titleKey)),
                    isSelected: kind == option,
                    config: .standard
                ) {
                    kind = option
                }
                if option.id != options.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
        }
    }

    private func send() async {
        guard let backend = environment.backend else { return }
        isSending = true
        defer { isSending = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await backend.suggestPlaceChange(
                placeID: place.id,
                kind: kind,
                changes: kind == .edit ? changes : nil,
                note: trimmed.isEmpty ? nil : trimmed
            )
            HapticManager.play(.confirm)
            isSent = true
        } catch {
            sendError = CommunityMessage.text(for: error)
            HapticManager.play(.fail)
        }
    }
}

// MARK: - Рядом

/// «Рядом»: похожие места поблизости (до 30 км), ближайшие первыми.
struct NearbyPlacesSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment
    let onSelect: (UUID) -> Void

    @State private var items: [PlaceItem] = []
    @State private var photoURLs: [String: URL] = [:]

    private static let radius = 30_000
    private static let count = 6

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionHeader(String(localized: "place.nearby"), systemImage: "location.circle")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: AppSpacing.md) {
                            ForEach(items) { item in
                                Button {
                                    onSelect(item.id)
                                } label: {
                                    PlaceItemCard(item: item, photoURL: item.photoPath.flatMap { photoURLs[$0] })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task(id: place.id) { await load() }
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        // Показанная точка места: у чужого приблизительного — смещённый центр, как на карте.
        let query = PlaceQuery(types: place.type.similarTypes, sort: .distance)
        guard let found = try? await backend.searchPlaces(query, near: place.coordinate, limit: Self.count + 1)
        else { return }
        let nearby = Array(
            found
                .filter { $0.id != place.id && ($0.distanceM ?? .max) <= Self.radius }
                .prefix(Self.count)
        )
        let paths = nearby.compactMap(\.photoPath)
        if !paths.isEmpty {
            photoURLs = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
        }
        items = nearby
    }
}
