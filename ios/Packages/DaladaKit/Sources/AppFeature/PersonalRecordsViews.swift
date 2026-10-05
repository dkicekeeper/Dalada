import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI

/// Личные рекорды: сеть, без неё — сохранённые (их же обновляет поздравление после отчёта).
struct RecordsLoader {
    let environment: AppEnvironment
    let userID: UUID

    func load() async -> [PersonalRecord] {
        if let backend = environment.backend, let records = try? await backend.myRecords() {
            try? await environment.cache.save(records, for: CacheKey.myRecords(userID))
            return records
        }
        return await saved()
    }

    func saved() async -> [PersonalRecord] {
        (try? await environment.cache.load([PersonalRecord].self, for: CacheKey.myRecords(userID))) ?? []
    }

    /// Новые рекорды в уловах только что сохранённого отчёта. Сравниваем с сохранёнными рекордами
    /// (если их ещё нет — пробуем сеть) и сразу запоминаем новые, чтобы следующий отчёт без сети
    /// сравнивался уже с ними.
    func check(_ catches: [CatchDraft], at date: Date) async -> [NewRecord] {
        guard !catches.isEmpty else { return [] }
        var records = await saved()
        if records.isEmpty, let backend = environment.backend, let loaded = try? await backend.myRecords() {
            records = loaded
        }
        let found = PersonalRecords.newRecords(in: catches, against: records)
        let updated = PersonalRecords.applying(catches, at: date, to: records)
        try? await environment.cache.save(updated, for: CacheKey.myRecords(userID))
        return found
    }
}

/// «Личные рекорды» над списком уловов: по каждому виду — самый тяжёлый и самый длинный улов.
struct PersonalRecordsSection: View {
    let records: [PersonalRecord]

    @Environment(SpeciesStore.self) private var speciesStore

    var body: some View {
        Section {
            ForEach(records) { record in
                row(record)
            }
        } header: {
            Text("records.title")
        } footer: {
            Text("records.footer")
        }
    }

    private func row(_ record: PersonalRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Image(systemName: "trophy")
                .foregroundStyle(AppColors.warning)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: speciesStore.name(for: record.speciesID))
                    .font(AppTypography.bodyEmphasis)
                if let best = bestLine(record) {
                    Text(verbatim: best)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textPrimary)
                }
                if let detail = detailLine(record) {
                    Text(verbatim: detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Text("records.caught \(record.totalCount)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    /// «4,2 кг · 85 см».
    private func bestLine(_ record: PersonalRecord) -> String? {
        let parts = [
            record.weight.map { CatchFormat.weight(grams: $0.value) },
            record.length.map { CatchFormat.length(millimeters: $0.value) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Где и когда пойман рекорд по весу (или по длине, если веса нет).
    private func detailLine(_ record: PersonalRecord) -> String? {
        guard let best = record.weight ?? record.length else { return nil }
        let date = best.at.formatted(.dateTime.day().month().year())
        return best.placeName.map { "\($0) · \(date)" } ?? date
    }
}

/// Строки поздравления: «Щука: 4,2 кг (было 3,1 кг)».
enum NewRecordText {
    @MainActor
    static func lines(_ records: [NewRecord], species: SpeciesStore) -> String {
        records.map { record in
            let format: (Int) -> String = record.measure == .weight
                ? { CatchFormat.weight(grams: $0) }
                : { CatchFormat.length(millimeters: $0) }
            return String(localized: "records.new.line \(species.name(for: record.speciesID)) \(format(record.value)) \(format(record.previous))")
        }
        .joined(separator: "\n")
    }
}
