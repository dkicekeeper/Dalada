import Foundation

/// Личный рекорд по виду рыбы — строка `my_records`: сколько поймано, самый тяжёлый и самый
/// длинный улов. Рекорд дают только записи с одной рыбой.
public struct PersonalRecord: Codable, Identifiable, Hashable, Sendable {
    /// Лучший улов по одной мере: вес (г) или длина (мм).
    public struct Best: Codable, Hashable, Sendable {
        public let value: Int
        public let at: Date
        public let catchID: UUID?
        public let placeName: String?

        public init(value: Int, at: Date, catchID: UUID? = nil, placeName: String? = nil) {
            self.value = value
            self.at = at
            self.catchID = catchID
            self.placeName = placeName
        }
    }

    public let speciesID: String
    public let totalCount: Int
    public let weight: Best?
    public let length: Best?

    public var id: String { speciesID }

    public init(speciesID: String, totalCount: Int, weight: Best? = nil, length: Best? = nil) {
        self.speciesID = speciesID
        self.totalCount = totalCount
        self.weight = weight
        self.length = length
    }

    enum CodingKeys: String, CodingKey {
        case speciesID = "species_id"
        case totalCount = "total_count"
        case weightG = "weight_g"
        case weightAt = "weight_at"
        case weightCatchID = "weight_catch_id"
        case weightPlaceName = "weight_place_name"
        case lengthMM = "length_mm"
        case lengthAt = "length_at"
        case lengthCatchID = "length_catch_id"
        case lengthPlaceName = "length_place_name"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speciesID = try c.decode(String.self, forKey: .speciesID)
        totalCount = try c.decode(Int.self, forKey: .totalCount)
        if let value = try c.decodeIfPresent(Int.self, forKey: .weightG), let at = try c.decodeIfPresent(Date.self, forKey: .weightAt) {
            weight = Best(
                value: value,
                at: at,
                catchID: try c.decodeIfPresent(UUID.self, forKey: .weightCatchID),
                placeName: try c.decodeIfPresent(String.self, forKey: .weightPlaceName)
            )
        } else {
            weight = nil
        }
        if let value = try c.decodeIfPresent(Int.self, forKey: .lengthMM), let at = try c.decodeIfPresent(Date.self, forKey: .lengthAt) {
            length = Best(
                value: value,
                at: at,
                catchID: try c.decodeIfPresent(UUID.self, forKey: .lengthCatchID),
                placeName: try c.decodeIfPresent(String.self, forKey: .lengthPlaceName)
            )
        } else {
            length = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(speciesID, forKey: .speciesID)
        try c.encode(totalCount, forKey: .totalCount)
        try c.encodeIfPresent(weight?.value, forKey: .weightG)
        try c.encodeIfPresent(weight?.at, forKey: .weightAt)
        try c.encodeIfPresent(weight?.catchID, forKey: .weightCatchID)
        try c.encodeIfPresent(weight?.placeName, forKey: .weightPlaceName)
        try c.encodeIfPresent(length?.value, forKey: .lengthMM)
        try c.encodeIfPresent(length?.at, forKey: .lengthAt)
        try c.encodeIfPresent(length?.catchID, forKey: .lengthCatchID)
        try c.encodeIfPresent(length?.placeName, forKey: .lengthPlaceName)
    }
}

/// Улов, побивший прежний рекорд вида.
public struct NewRecord: Identifiable, Hashable, Sendable {
    public enum Measure: String, Sendable {
        /// Граммы.
        case weight
        /// Миллиметры.
        case length
    }

    public let speciesID: String
    public let measure: Measure
    public let value: Int
    public let previous: Int

    public var id: String { speciesID + "/" + measure.rawValue }

    public init(speciesID: String, measure: Measure, value: Int, previous: Int) {
        self.speciesID = speciesID
        self.measure = measure
        self.value = value
        self.previous = previous
    }
}

/// Сравнение уловов отчёта с рекордами — для поздравления сразу после сохранения, в том числе без
/// сети (по сохранённым рекордам).
public enum PersonalRecords {
    /// Рекорд не дают «другая рыба» и записи с несколькими рыбами (вес и длина — на всех).
    static func counts(_ draft: CatchDraft) -> Bool {
        draft.speciesID != "other" && draft.count == 1
    }

    /// Уловы тяжелее или длиннее прежнего рекорда своего вида; по каждому виду и мере — лучший.
    /// Первый улов вида (или первый с весом, с длиной) рекордом не считается.
    public static func newRecords(in catches: [CatchDraft], against records: [PersonalRecord]) -> [NewRecord] {
        let bySpecies = Dictionary(records.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
        var best: [String: NewRecord] = [:]
        for draft in catches where counts(draft) {
            guard let record = bySpecies[draft.speciesID] else { continue }
            let candidates: [(NewRecord.Measure, Int?, PersonalRecord.Best?)] = [
                (.weight, draft.weightGrams, record.weight),
                (.length, draft.lengthMillimeters, record.length),
            ]
            for (measure, value, previous) in candidates {
                guard let value, let previous, value > previous.value else { continue }
                let found = NewRecord(speciesID: draft.speciesID, measure: measure, value: value, previous: previous.value)
                if let current = best[found.id], current.value >= value { continue }
                best[found.id] = found
            }
        }
        return best.values.sorted { ($0.speciesID, $0.measure.rawValue) < ($1.speciesID, $1.measure.rawValue) }
    }

    /// Рекорды после этих уловов — чтобы следующий отчёт без сети сравнивался уже с ними.
    public static func applying(_ catches: [CatchDraft], at date: Date, to records: [PersonalRecord]) -> [PersonalRecord] {
        var bySpecies = Dictionary(records.map { ($0.speciesID, $0) }, uniquingKeysWith: { first, _ in first })
        var order = records.map(\.speciesID)
        for draft in catches where draft.speciesID != "other" {
            let record = bySpecies[draft.speciesID]
            if record == nil { order.append(draft.speciesID) }
            var weight = record?.weight
            var length = record?.length
            if counts(draft) {
                if let grams = draft.weightGrams, grams > (weight?.value ?? 0) {
                    weight = PersonalRecord.Best(value: grams, at: date)
                }
                if let millimeters = draft.lengthMillimeters, millimeters > (length?.value ?? 0) {
                    length = PersonalRecord.Best(value: millimeters, at: date)
                }
            }
            bySpecies[draft.speciesID] = PersonalRecord(
                speciesID: draft.speciesID,
                totalCount: (record?.totalCount ?? 0) + draft.count,
                weight: weight,
                length: length
            )
        }
        return order.compactMap { bySpecies[$0] }
    }
}
