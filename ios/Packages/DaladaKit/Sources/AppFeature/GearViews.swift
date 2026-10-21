import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Форматы

enum GearFormat {
    /// «750 г», «8,2 кг».
    static func weight(_ grams: Int) -> String {
        if grams >= 1000 {
            return Measurement(value: Double(grams) / 1000, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
        return Measurement(value: Double(grams), unit: UnitMass.grams)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// «14 предметов · 8,2 кг» (вес — если указан хоть у одного).
    static func summary(_ items: [GearItem]) -> String {
        let summary = GearCategorySummary.make(items)
        let count = summary.reduce(0) { $0 + $1.count }
        let grams = summary.reduce(0) { $0 + $1.weightGrams }
        let countText = String(localized: "gear.count \(count)")
        return grams > 0 ? countText + " · " + weight(grams) : countText
    }
}

// MARK: - Моя экипировка

/// «Моя экипировка»: предметы по категориям, сводка по количеству и весу, статусы.
struct GearListView: View {
    @Environment(ListsStore.self) private var lists
    @State private var editing: GearItem?
    @State private var addsPopular = false
    /// Выбранная метка: в списке и сводке — только предметы с ней.
    @State private var tag: String?
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<UUID> = []
    /// Предметы, удаление которых ждёт подтверждения.
    @State private var pendingDelete: [GearItem] = []

    private var tags: [String] { GearItem.allTags(lists.gear) }
    /// Предметы с выбранной меткой (без метки — все).
    private var shown: [GearItem] {
        guard let tag else { return lists.gear }
        return lists.gear.filter { $0.hasTag(tag) }
    }
    private var summaries: [GearCategorySummary] { GearCategorySummary.make(shown) }

    // DesignKit 8.0.0: категории — CardList в стеклянных секциях; долгое нажатие — «Изменить» и
    // «Удалить», в панели — выбор нескольких, свой порядок внутри категории и «+» (до этого List со
    // смахиванием). Порядок меняется без фильтра по метке.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if lists.gear.isEmpty {
                    EmptyState(
                        icon: "backpack",
                        title: String(localized: "gear.empty.title"),
                        description: String(localized: "gear.empty.description"),
                        actionTitle: String(localized: "gear.addPopular"),
                        action: { addsPopular = true }
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if !tags.isEmpty, mode == .browsing {
                            GearTagFilter(tags: tags, selection: $tag)
                        }
                        GearSummaryView(items: shown)
                    }
                    .cardContentPadding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    ForEach(summaries) { summary in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            GearCategoryHeader(
                                category: summary.category,
                                trailing: summary.weightGrams > 0 ? GearFormat.weight(summary.weightGrams) : nil
                            )
                            CardList(
                                shown.filter { $0.category == summary.category },
                                layout: .section,
                                mode: mode,
                                selection: $selection,
                                onMove: tag == nil ? { lists.moveGear(in: summary.category, from: $0, to: $1) } : nil
                            ) { item in
                                Button {
                                    editing = item
                                } label: {
                                    GearRow(item: item)
                                        .padding(.vertical, AppSpacing.md)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("common.edit", systemImage: "pencil") { editing = item }
                                    Button("common.delete", systemImage: "trash", role: .destructive) {
                                        pendingDelete = [item]
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: shown.map(\.id),
            canReorder: tag == nil,
            onDeleteSelected: { pendingDelete = shown.filter { selection.contains($0.id) } }
        )
        .confirmationDialog(
            pendingDelete.count == 1
                ? LocalizedStringKey("gear.deleteConfirm")
                : LocalizedStringKey("common.deleteSelectedConfirm \(pendingDelete.count)"),
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("common.delete", role: .destructive) {
                for item in pendingDelete { lists.delete(item) }
                pendingDelete = []
                selection = []
                mode = .browsing
            }
        }
        .navigationTitle("gear.title")
        // Метку убрали со всех предметов — фильтр снимается.
        .onChange(of: tags) { _, tags in
            if let tag, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                self.tag = nil
            }
        }
        .toolbar {
            if mode == .browsing {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editing = GearItem(name: "")
                        } label: {
                            Label("gear.new", systemImage: "plus")
                        }
                        Button {
                            addsPopular = true
                        } label: {
                            Label("gear.addPopular", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("gear.new"))
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            GearFormView(item: item, isNew: lists.gearItem(item.id) == nil)
                .environment(lists)
        }
        .sheet(isPresented: $addsPopular) {
            PopularGearView()
                .environment(lists)
        }
        .task { await lists.loadTemplates() }
    }
}

/// Сводка: сколько предметов, общий вес, сколько в ремонте и что купить.
struct GearSummaryView: View {
    let items: [GearItem]

    private var repairCount: Int { items.filter { $0.status == .repair }.count }
    private var buyCount: Int { items.filter { $0.status == .buy }.count }
    private var hasUnknownWeight: Bool { items.contains { $0.weightGrams == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: GearFormat.summary(items))
                .font(AppTypography.bodyEmphasis)
            if hasUnknownWeight {
                Text("gear.summary.unknownWeight")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            if repairCount > 0 || buyCount > 0 {
                HStack(spacing: AppSpacing.md) {
                    if repairCount > 0 {
                        Label("gear.summary.repair \(repairCount)", systemImage: GearStatus.repair.systemImage)
                            .foregroundStyle(AppColors.warning)
                    }
                    if buyCount > 0 {
                        Label("gear.summary.buy \(buyCount)", systemImage: GearStatus.buy.systemImage)
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .font(AppTypography.caption)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// Метки снаряжения чипами в несколько строк (`FlowLayout` DesignKit): нажатие — показать только
/// предметы с меткой, повторное — все.
struct GearTagFilter: View {
    let tags: [String]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: AppSpacing.xs, lineSpacing: AppSpacing.xs) {
            ForEach(tags, id: \.self) { tag in
                let isSelected = selection.map { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? false
                Button {
                    withAnimation(AppAnimation.snappy) { selection = isSelected ? nil : tag }
                } label: {
                    Text(verbatim: tag)
                        .font(AppTypography.bodySmall)
                }
                .buttonStyle(.plain)
                .filterChipStyle(isSelected: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

/// Предмет: название, бренд, количество, вес, статус (если не «в порядке»); `ItemRow` из DesignKit.
struct GearRow: View {
    let item: GearItem

    var body: some View {
        ItemRow(item.name, meta: details.isEmpty ? [] : [MetaLine(details)], titleFont: AppTypography.body) {
            if item.status != .ok {
                Label(LocalizedStringKey(item.status.titleKey), systemImage: item.status.systemImage)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(item.status == .repair ? AppColors.warning : AppColors.accent)
            }
        }
    }

    /// «Shimano · ×2 · 620 г».
    private var details: [MetaItem] {
        var parts: [MetaItem] = []
        if let brand = item.brand { parts.append(.text(brand)) }
        if item.quantity > 1 { parts.append(.text("×\(item.quantity)")) }
        if let total = item.totalWeightGrams { parts.append(.text(GearFormat.weight(total))) }
        return parts
    }
}

// MARK: - Предмет

/// Новый предмет или правка: название, категория, бренд, вес, количество, статус, метки, заметка.
struct GearFormView: View {
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var draft: GearItem
    @State private var brand: String
    @State private var note: String
    @State private var confirmsDelete = false

    init(item: GearItem, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: item)
        _brand = State(initialValue: item.brand ?? "")
        _note = State(initialValue: item.note ?? "")
    }

    private var edited: GearItem {
        var item = draft
        item.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.tags = GearItem.normalizedTags(draft.tags)
        return item
    }

    /// Подсказки меток: свои, уже поставленные другим предметам, затем — из готового набора.
    private var tagSuggestions: [String] {
        let own = GearItem.allTags(lists.gear)
        let common = String(localized: "gear.tags.suggestions")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return GearItem.normalizedTags(own + common.filter { tag in
            !own.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        })
    }

    var body: some View {
        EditSheetContainer(
            title: isNew ? String(localized: "gear.new") : draft.name,
            isSaveDisabled: !edited.isValid,
            wrapInForm: false,
            onSave: {
                lists.save(edited)
                dismiss()
            },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection {
                        FormTextField(text: $draft.name, placeholder: String(localized: "gear.form.name"), style: .row)
                        UniversalRow(
                            String(localized: "gear.form.category"),
                            accessory: .menu($draft.category, options: GearCategory.allCases.map {
                                (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                            })
                        )
                        FormTextField(text: $brand, placeholder: String(localized: "gear.form.brand"), style: .row)
                    }

                    FormSection(footer: String(localized: "gear.form.weightFooter")) {
                        UniversalRow(title: String(localized: "gear.form.weight")) {
                            TextField("gear.form.weightPlaceholder", value: $draft.weightGrams, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        UniversalRow(
                            String(localized: "gear.form.quantity"),
                            accessory: .stepper($draft.quantity, in: 1...999)
                        )
                    }

                    FormSection(header: String(localized: "gear.form.status")) {
                        SegmentedPicker(
                            title: String(localized: "gear.form.status"),
                            selection: $draft.status,
                            options: GearStatus.allCases.map {
                                (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                            }
                        )
                        .padding(.vertical, AppSpacing.md)
                    }

                    FormSection(header: String(localized: "gear.form.tags"), footer: String(localized: "gear.form.tagsFooter")) {
                        TagInput(
                            String(localized: "gear.form.tagsPlaceholder"),
                            tags: $draft.tags,
                            suggestions: tagSuggestions,
                            maxTags: GearItem.tagLimit
                        )
                        .padding(.vertical, AppSpacing.md)
                    }

                    FormSection(header: String(localized: "gear.form.note")) {
                        FormTextField(
                            text: $note,
                            placeholder: String(localized: "gear.form.notePlaceholder"),
                            style: .rowMultiline(min: 2, max: 6)
                        )
                    }

                    if !isNew {
                        FormSection {
                            UniversalRow(
                                String(localized: "gear.delete"),
                                role: .destructive,
                                accessory: .action {
                                    confirmsDelete = true
                                }
                            )
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
        .confirmationDialog("gear.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("gear.delete", role: .destructive) {
                lists.delete(draft)
                dismiss()
            }
        }
    }
}

// MARK: - Быстрое добавление

/// Популярные предметы из шаблонов редакции: отметить нужные и добавить разом.
struct PopularGearView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var selected: Set<String> = []

    private var items: [ChecklistTemplate.Item] { ChecklistTemplate.popularItems(lists.templates) }

    /// Уже есть в экипировке (по названию).
    private var owned: Set<String> { Set(lists.gear.map { $0.name.lowercased() }) }

    var body: some View {
        NavigationStack {
            // DesignKit 8.0.0: стеклянные секции на странице (до этого List).
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    if items.isEmpty {
                        Text("checklists.templates.unavailable")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    ForEach(GearCategory.allCases) { category in
                        let inCategory = items.filter { $0.category == category }
                        if !inCategory.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                GearCategoryHeader(category: category)
                                FormSection {
                                    ForEach(inCategory) { item in
                                        row(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("gear.addPopular")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("gear.addSelected \(selected.count)") {
                        lists.addPopular(items.filter { selected.contains($0.id) }, language: PackingFormat.language)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await lists.loadTemplates() }
        }
    }

    private func row(_ item: ChecklistTemplate.Item) -> some View {
        let title = item.title.text(for: PackingFormat.language)
        let isOwned = owned.contains(title.lowercased())
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                SelectionIndicator(isSelected: isOwned || isSelected, tint: isOwned ? AppColors.textTertiary : AppColors.accent)
                Text(verbatim: title)
                    .foregroundStyle(isOwned ? AppColors.textSecondary : AppColors.textPrimary)
                Spacer(minLength: 0)
                if isOwned {
                    Text("gear.popular.owned")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.vertical, AppSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Под текстом: после круга выбора и промежутка (метка кнопки не передаёт отступ).
        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
        .accessibilityAddTraits(isOwned || isSelected ? .isSelected : [])
        .disabled(isOwned)
    }
}

/// Выбор предметов своей экипировки для чеклиста.
struct GearPickerView: View {
    /// Уже есть в чеклисте.
    let excluded: Set<UUID>
    let onPick: @MainActor ([GearItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ListsStore.self) private var lists
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            // DesignKit 8.0.0: стеклянные секции на странице (до этого List).
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    ForEach(GearCategorySummary.make(lists.gear)) { summary in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            GearCategoryHeader(category: summary.category)
                            FormSection {
                                ForEach(lists.gear.filter { $0.category == summary.category }) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("checklist.addFromGear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("gear.addSelected \(selected.count)") {
                        onPick(lists.gear.filter { selected.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(_ item: GearItem) -> some View {
        let isAdded = excluded.contains(item.id)
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                SelectionIndicator(isSelected: isAdded || isSelected, tint: isSelected ? AppColors.accent : AppColors.textTertiary)
                GearRow(item: item)
            }
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Под текстом: после круга выбора и промежутка (метка кнопки не передаёт отступ).
        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
        .accessibilityAddTraits(isAdded || isSelected ? .isSelected : [])
        .disabled(isAdded)
    }
}
