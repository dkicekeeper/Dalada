import Foundation
import Testing
@testable import DaladaCore

@Suite("Личные рекорды")
struct PersonalRecordsTests {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private var records: [PersonalRecord] {
        [
            PersonalRecord(
                speciesID: "pike",
                totalCount: 4,
                weight: .init(value: 3100, at: day),
                length: .init(value: 700, at: day)
            ),
            PersonalRecord(speciesID: "perch", totalCount: 3, weight: .init(value: 300, at: day)),
        ]
    }

    @Test func decodesServerRow() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([PersonalRecord].self, from: Data("""
        [{"species_id": "pike", "total_count": 6,
          "weight_g": 4200, "weight_at": "2026-07-01T05:00:00Z",
          "weight_catch_id": "dddddddd-0000-0000-0000-000000000002", "weight_place_name": "Озеро",
          "length_mm": null, "length_at": null, "length_catch_id": null, "length_place_name": null}]
        """.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].weight?.value == 4200)
        #expect(rows[0].weight?.placeName == "Озеро")
        #expect(rows[0].length == nil)
        // Сохранённая копия читается обратно.
        let copy = try JSONDecoder().decode([PersonalRecord].self, from: JSONEncoder().encode(rows))
        #expect(copy == rows)
    }

    @Test func heavierCatchIsANewRecord() {
        let found = PersonalRecords.newRecords(
            in: [CatchDraft(speciesID: "pike", weightKg: 4.2)],
            against: records
        )
        #expect(found == [NewRecord(speciesID: "pike", measure: .weight, value: 4200, previous: 3100)])
    }

    @Test func weightAndLengthSeparately() {
        let found = PersonalRecords.newRecords(
            in: [CatchDraft(speciesID: "pike", weightKg: 2.0, lengthCm: 85)],
            against: records
        )
        #expect(found == [NewRecord(speciesID: "pike", measure: .length, value: 850, previous: 700)])
    }

    @Test func equalIsNotARecord() {
        #expect(PersonalRecords.newRecords(in: [CatchDraft(speciesID: "perch", weightKg: 0.3)], against: records).isEmpty)
    }

    @Test func firstCatchOfASpeciesIsNotARecord() {
        #expect(PersonalRecords.newRecords(in: [CatchDraft(speciesID: "zander", weightKg: 5)], against: records).isEmpty)
        // Окунь без рекорда длины — первая длина тоже не рекорд.
        #expect(PersonalRecords.newRecords(in: [CatchDraft(speciesID: "perch", lengthCm: 30)], against: records).isEmpty)
    }

    @Test func severalFishOrOtherFishDoNotCount() {
        let catches = [
            CatchDraft(speciesID: "pike", weightKg: 9, count: 3),
            CatchDraft(speciesID: "other", weightKg: 20),
        ]
        #expect(PersonalRecords.newRecords(in: catches, against: records + [PersonalRecord(speciesID: "other", totalCount: 1, weight: .init(value: 1, at: day))]).isEmpty)
    }

    @Test func bestOfSeveralInOneReport() {
        let found = PersonalRecords.newRecords(
            in: [CatchDraft(speciesID: "pike", weightKg: 3.5), CatchDraft(speciesID: "pike", weightKg: 4.1)],
            against: records
        )
        #expect(found == [NewRecord(speciesID: "pike", measure: .weight, value: 4100, previous: 3100)])
    }

    @Test func applyingKeepsTheNextReportHonest() {
        let updated = PersonalRecords.applying(
            [CatchDraft(speciesID: "pike", weightKg: 4.2), CatchDraft(speciesID: "zander", weightKg: 2, count: 2)],
            at: day,
            to: records
        )
        let pike = updated.first { $0.speciesID == "pike" }
        #expect(pike?.weight?.value == 4200)
        #expect(pike?.length?.value == 700)
        #expect(pike?.totalCount == 5)
        // Новый вид появляется со счётчиком, но без рекорда веса (две рыбы).
        let zander = updated.first { $0.speciesID == "zander" }
        #expect(zander?.totalCount == 2)
        #expect(zander?.weight == nil)
        // Тот же улов ещё раз — уже не рекорд.
        #expect(PersonalRecords.newRecords(in: [CatchDraft(speciesID: "pike", weightKg: 4.2)], against: updated).isEmpty)
    }
}
