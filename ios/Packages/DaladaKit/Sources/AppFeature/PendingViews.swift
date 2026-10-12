import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import Sync

/// Условия одной строкой: «Клёв: хороший · Людей: немного · Вода: мутная · +18° · 3 м/с СВ · 689 мм»
/// (погоду в отчёт подставляет телефон).
enum ConditionsText {
    static func make(_ conditions: CheckinConditions) -> String? {
        let pairs: [(String, String?)] = [
            ("conditions.bite", conditions.bite?.titleKey),
            ("conditions.crowd", conditions.crowd?.titleKey),
            ("conditions.water", conditions.water?.titleKey),
            ("conditions.road", conditions.road?.titleKey),
        ]
        let parts = pairs.compactMap { pair -> String? in
            let (category, value) = pair
            guard let value else { return nil }
            let categoryTitle = String(localized: String.LocalizationValue(category))
            let valueTitle = String(localized: String.LocalizationValue(value)).lowercased()
            return categoryTitle + ": " + valueTitle
        }
        let all = parts + [conditions.weather.flatMap(WeatherText.summary)].compactMap { $0 }
        return all.isEmpty ? nil : all.joined(separator: " · ")
    }
}

/// Свой чекин, ещё не принятый сервером: как отчёт, но с состоянием отправки
/// (`PendingItemCard` из DesignKit). В карточке места заголовок — «Вы», в профиле — название места.
struct PendingReportRow: View {
    let item: PendingCheckin
    var showsPlace = false

    @Environment(SpeciesStore.self) private var speciesStore
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        PendingItemCard(
            title: showsPlace ? item.placeName : String(localized: "report.you"),
            date: item.at,
            state: PendingItemState(item.state),
            onRetry: { await sync.retry(item.id) },
            onDiscard: { await sync.discard(item.id) }
        ) {
            if let conditions = ConditionsText.make(item.conditions) {
                Text(verbatim: conditions)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                Text(verbatim: note)
                    .font(AppTypography.bodySmall)
            }

            ForEach(item.catches) { catchDraft in
                CatchSummaryRow(
                    speciesName: speciesStore.name(for: catchDraft.speciesID),
                    count: catchDraft.count,
                    weightGrams: catchDraft.weightGrams,
                    lengthMillimeters: catchDraft.lengthMillimeters,
                    released: catchDraft.released
                )
            }

            if item.photoCount > 0 {
                Label {
                    Text(verbatim: "\(item.photoCount)")
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

extension PendingItemState {
    /// Состояние из очереди отправки (чекины и поездки).
    init(_ state: PendingCheckin.State) {
        switch state {
        case .waiting: self = .waiting
        case .failed(let message): self = .failed(message: message)
        }
    }
}

/// «Ожидают отправки» в профиле: все поездки и чекины из очереди и «Отправить сейчас».
struct PendingQueueSection: View {
    @Environment(SyncEngine.self) private var sync

    private var hasWaiting: Bool {
        sync.pending.contains { $0.state == .waiting } || sync.pendingTrips.contains { $0.state == .waiting }
    }

    var body: some View {
        if !sync.pending.isEmpty || !sync.pendingTrips.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "pending.title")) {
                    if sync.isSending {
                        // Отправка идёт — слои значка загораются по очереди (DesignKit).
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(AppColors.accent)
                            .symbolPulse(.working)
                            .accessibilityLabel(Text("pending.sending"))
                    } else if hasWaiting {
                        Button("pending.sendNow") {
                            sync.kick(force: true)
                        }
                    }
                }
                ForEach(sync.pendingTrips) { item in
                    PendingTripRow(item: item)
                }
                ForEach(sync.pending) { item in
                    PendingReportRow(item: item, showsPlace: true)
                }
            }
        }
    }
}
