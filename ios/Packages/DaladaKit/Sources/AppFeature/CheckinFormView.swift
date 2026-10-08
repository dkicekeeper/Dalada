import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import PhotosUI
import SwiftUI
import Sync

/// Чекин «Я здесь»: как клюёт, людность, вода, дорога, уловы, фото, заметка, видимость.
/// Всё, кроме места, необязательно — чекин должен занимать 10 секунд.
/// Сохраняется в офлайн-очередь и уходит на сервер сразу или когда появится сеть.
struct CheckinFormView: View {
    let placeName: String
    /// Точка места — для подсказок о запретах и промысловой мере.
    let coordinate: GeoPoint?
    /// Рекорды автора: после сохранения — поздравление с новым рекордом (`nil` — гость).
    let records: RecordsLoader?
    /// Погода у места подставляется в отчёт сама (`nil` — без погоды).
    let weatherCache: CacheStore?
    let onSaved: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(RulesStore.self) private var rules
    @Environment(SyncEngine.self) private var sync
    @State private var draft: CheckinDraft
    @State private var editingCatch: CatchDraft?
    @State private var locationState: LocationState = .locating
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoFailed = false
    /// Отчёт сохранён и побил рекорды: поздравление, потом форма закрывается.
    @State private var newRecords: [NewRecord] = []
    @State private var showsNewRecords = false

    enum LocationState: Equatable {
        case locating
        case found
        case unavailable
    }

    init(
        placeID: UUID,
        placeName: String,
        coordinate: GeoPoint? = nil,
        records: RecordsLoader? = nil,
        weatherCache: CacheStore? = nil,
        onSaved: @escaping @MainActor () -> Void
    ) {
        self.placeName = placeName
        self.coordinate = coordinate
        self.records = records
        self.weatherCache = weatherCache
        self.onSaved = onSaved
        _draft = State(initialValue: CheckinDraft(placeID: placeID))
    }

    /// Запреты, которые действуют здесь в день чекина (мягкое предупреждение, без блокировки).
    private var activeBans: [Regulation] {
        guard let coordinate, let pack = rules.pack else { return [] }
        return pack.activeBans(at: coordinate, on: CalendarDay(draft.at, calendar: RulesStore.almatyCalendar))
    }

    /// Промысловая мера в этом месте: вид → см.
    private var minSizes: [String: Int] {
        guard let coordinate, let pack = rules.pack else { return [:] }
        return pack.minSizes(at: coordinate)
    }

    var body: some View {
        EditSheetContainer(
            title: placeName,
            isSaveDisabled: !draft.isValid || isProcessingPhotos || showsNewRecords,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if !activeBans.isEmpty, let pack = rules.pack {
                        ForEach(activeBans) { ban in
                            RecommendationBox(
                                text: String(localized: "rules.checkin.banWarning \(ban.title.text(for: RulesStore.language)) \(RuleFormat.statusText(pack.status(of: ban, on: CalendarDay(draft.at, calendar: RulesStore.almatyCalendar))).lowercased())"),
                                color: AppColors.destructive,
                                icon: "nosign"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        FormSection(header: String(localized: "checkin.form.conditions")) {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                FormChipRow(String(localized: "conditions.bite"), options: CheckinConditions.Bite.allCases, selection: $draft.conditions.bite) { $0.title }
                                FormChipRow(String(localized: "conditions.crowd"), options: CheckinConditions.Crowd.allCases, selection: $draft.conditions.crowd) { $0.title }
                                FormChipRow(String(localized: "conditions.water"), options: CheckinConditions.Water.allCases, selection: $draft.conditions.water) { $0.title }
                                FormChipRow(String(localized: "conditions.road"), options: CheckinConditions.Road.allCases, selection: $draft.conditions.road) { $0.title }
                            }
                            .padding(.vertical, AppSpacing.md)
                        }
                        if let weather = draft.conditions.weather, let summary = WeatherText.summary(weather) {
                            footerLabel(
                                String(localized: "weather.inReport \(summary)"),
                                systemImage: WeatherKind(code: weather.code)?.systemImage ?? "thermometer.medium"
                            )
                        }
                    }

                    FormSection(header: String(localized: "checkin.form.catches")) {
                        ForEach(draft.catches) { catchDraft in
                            Button {
                                editingCatch = catchDraft
                            } label: {
                                CatchSummaryRow(
                                    speciesName: speciesStore.name(for: catchDraft.speciesID),
                                    count: catchDraft.count,
                                    weightGrams: catchDraft.weightGrams,
                                    lengthMillimeters: catchDraft.lengthMillimeters,
                                    released: catchDraft.released,
                                    hasPhoto: catchDraft.photo != nil
                                )
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)
                            }
                            .buttonStyle(.plain)
                            // Удалить улов: смахиванием (iOS 27) и долгим нажатием.
                            .swipeActions {
                                removeCatchButton(catchDraft)
                            }
                            .contextMenu {
                                removeCatchButton(catchDraft)
                            }
                            Divider().padding(.leading, AppSpacing.lg)
                        }

                        Button {
                            editingCatch = CatchDraft(speciesID: speciesStore.species.first?.id ?? "common_carp")
                        } label: {
                            UniversalRow(
                                leadingIcon: .sfSymbol("plus.circle", color: AppColors.accent, size: AppIconSize.lg),
                                title: String(localized: "checkin.form.addCatch"),
                                titleColor: AppColors.accent
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    FormSection(
                        header: String(localized: "checkin.form.photos"),
                        footer: photoFailed ? nil : String(localized: "checkin.form.photosFooter")
                    ) {
                        if !draft.photos.isEmpty {
                            PhotoDraftStrip(photos: draft.photos) { id in
                                draft.photos.removeAll { $0.id == id }
                            }
                            .contentMargins(.horizontal, AppSpacing.lg, for: .scrollContent)
                            .padding(.vertical, AppSpacing.md)
                        }
                        if isProcessingPhotos {
                            // Фото сжимаются: плитка-скелетон на месте будущего фото.
                            PhotoTileSkeleton()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)
                        } else if draft.photos.count < CheckinDraft.photoLimit {
                            PhotosPicker(
                                selection: $pickerItems,
                                maxSelectionCount: CheckinDraft.photoLimit - draft.photos.count,
                                matching: .images
                            ) {
                                PickerRowLabel(String(localized: "checkin.form.addPhotos"), systemImage: "photo.on.rectangle.angled")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if photoFailed {
                        InlineStatusText(message: String(localized: "photo.failed"), type: .error)
                    }

                    FormSection(header: String(localized: "checkin.form.note")) {
                        FormTextField(
                            text: $draft.note,
                            placeholder: String(localized: "checkin.form.notePlaceholder"),
                            style: .rowMultiline(min: 2, max: 6)
                        )
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        FormSection(header: String(localized: "place.form.visibility")) {
                            SegmentedPicker(
                                title: String(localized: "place.form.visibility"),
                                selection: $draft.visibility,
                                options: DaladaCore.Visibility.allCases.map {
                                    (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                                }
                            )
                            .padding(AppSpacing.md)
                        }
                        locationFooter
                    }

                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
            .swipeActionsContainerIfAvailable()
        }
        .sheet(item: $editingCatch) { catchDraft in
            CatchFormView(draft: catchDraft, minSizes: minSizes) { updated in
                if let index = draft.catches.firstIndex(where: { $0.id == updated.id }) {
                    draft.catches[index] = updated
                } else {
                    draft.catches.append(updated)
                }
            }
            .environment(speciesStore)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .alert("records.new.title", isPresented: $showsNewRecords) {
            Button("common.ok") { close() }
        } message: {
            Text(verbatim: NewRecordText.lines(newRecords, species: speciesStore))
        }
        .interactiveDismissDisabled(isSaving || showsNewRecords)
        .task { await locate() }
        .task { await loadWeather() }
        .task { await speciesStore.loadIfNeeded() }
    }

    private func removeCatchButton(_ catchDraft: CatchDraft) -> some View {
        Button("catch.delete", systemImage: "trash", role: .destructive) {
            draft.catches.removeAll { $0.id == catchDraft.id }
        }
    }

    /// Подпись под карточкой со значком — как подвал `FormSection`.
    private func footerLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.lg)
    }

    private var locationFooter: some View {
        switch locationState {
        case .locating:
            footerLabel(String(localized: "checkin.location.locating"), systemImage: "location")
        case .found:
            footerLabel(String(localized: "checkin.location.found"), systemImage: "location.fill")
        case .unavailable:
            footerLabel(String(localized: "checkin.location.unavailable"), systemImage: "location.slash")
        }
    }

    /// Погода у места сейчас — в отчёт. Без сети — сохранённый прогноз не старше трёх часов, иначе без погоды.
    private func loadWeather() async {
        guard let weatherCache, let coordinate,
              let forecast = await PlaceWeatherLoader(cache: weatherCache).load(at: coordinate, maxStale: 3 * 3600)
        else { return }
        let snapshot = forecast.current.forReport
        guard !snapshot.isEmpty else { return }
        draft.conditions.weather = snapshot
    }

    private func locate() async {
        if let location = await DeviceLocation.current() {
            draft.deviceLocation = location
            locationState = .found
        } else {
            locationState = .unavailable
        }
    }

    /// Сжимает выбранные фото по одному и добавляет в чекин (не больше лимита).
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        isProcessingPhotos = true
        photoFailed = false
        defer { isProcessingPhotos = false }
        for item in items {
            guard draft.photos.count < CheckinDraft.photoLimit else { break }
            if let photo = await PhotoCompressor.draft(from: item) {
                draft.photos.append(photo)
            } else {
                photoFailed = true
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var checkin = draft
        checkin.at = Date()
        do {
            // Сохраняется на телефоне сразу; на сервер — когда получится.
            try await sync.submit(checkin, placeName: placeName)
        } catch {
            saveError = String(localized: "checkin.save.failed")
            return
        }
        // Новый личный рекорд — поздравление, форма закроется после «OK».
        let found = await records?.check(checkin.catches, at: checkin.at) ?? []
        if !found.isEmpty {
            newRecords = found
            showsNewRecords = true
            return
        }
        close()
    }

    private func close() {
        onSaved()
        dismiss()
        // Первый чекин — момент первой пользы: объясним, зачем уведомления.
        Task { await NotificationPrimer.shared.offer() }
    }
}

/// Варианты условий с ключом названия в `Localizable.xcstrings`.
protocol TitledOption {
    var titleKey: String { get }
}

extension TitledOption {
    /// Локализованное название для `ChipPicker`.
    var title: String { String(localized: String.LocalizationValue(titleKey)) }
}

extension CheckinConditions.Bite: TitledOption {}
extension CheckinConditions.Crowd: TitledOption {}
extension CheckinConditions.Water: TitledOption {}
extension CheckinConditions.Road: TitledOption {}

/// Краткая строка улова: «Щука ×2 · 2,5 кг · 65 см · отпущена».
struct CatchSummaryRow: View {
    let speciesName: String
    let count: Int
    let weightGrams: Int?
    let lengthMillimeters: Int?
    let released: Bool
    var hasPhoto = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "fish")
                .foregroundStyle(AppColors.accent)
            Text(verbatim: summary)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
            if hasPhoto {
                Image(systemName: "camera.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel(Text("catch.form.photo"))
            }
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        var parts = [count > 1 ? "\(speciesName) ×\(count)" : speciesName]
        if let weightGrams {
            parts.append(CatchFormat.weight(grams: weightGrams))
        }
        if let lengthMillimeters {
            parts.append(CatchFormat.length(millimeters: lengthMillimeters))
        }
        if released {
            parts.append(String(localized: "catch.released"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Вес и длина улова: «2,5 кг», «65 см».
enum CatchFormat {
    static func weight(grams: Int) -> String {
        Measurement(value: Double(grams) / 1000, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }

    static func length(millimeters: Int) -> String {
        Measurement(value: Double(millimeters) / 10, unit: UnitLength.centimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
