import Foundation
import Testing
@testable import DaladaCore

@Suite("Shared packing")
struct SharedPackingTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesSummaryAndItems() throws {
        let summary = """
        [{"id": "aaaaaaaa-0000-0000-0000-000000000001", "owner_id": "11111111-1111-1111-1111-111111111111",
          "owner_username": "arman", "owner_display_name": null, "title": "Капшагай", "trip_date": "2026-10-12",
          "members_count": 2, "items_count": 14, "done_count": 5, "is_own": false,
          "updated_at": "2026-10-05T12:00:00Z"}]
        """
        let row = try decoder.decode([SharedPackingSummary].self, from: Data(summary.utf8)).first
        #expect(row?.tripDate == CalendarDay(year: 2026, month: 10, day: 12))
        #expect(row?.ownerName == "@arman")
        #expect(row?.doneCount == 5)

        let items = """
        [{"id": "bbbbbbbb-0000-0000-0000-000000000002", "title": "Котелок", "category": null, "item_position": 3,
          "assignee_id": null, "done": false, "created_by": null, "updated_at": "2026-10-05T12:00:00Z"},
         {"id": "bbbbbbbb-0000-0000-0000-000000000001", "title": "Палатка", "category": "camp", "item_position": 1,
          "assignee_id": "22222222-2222-2222-2222-222222222222", "done": true, "created_by": null,
          "updated_at": "2026-10-05T12:00:00Z"}]
        """
        let decoded = try decoder.decode([SharedPackingItem].self, from: Data(items.utf8))
        #expect(SharedPacking.unassignedCount(decoded) == 1)
        let groups = SharedPacking.grouped(decoded)
        #expect(groups.last?.category == nil)
        #expect(groups.last?.items.map(\.title) == ["Котелок"])
    }

    @Test func itemsFromChecklistDropChecks() {
        let checklist = Checklist(
            kind: .packing,
            title: "Сборы",
            items: [ChecklistItem(title: "Палатка", category: .camp, isChecked: true), ChecklistItem(title: "Спички")]
        )
        let drafts = SharedPacking.items(from: checklist)
        #expect(drafts == [
            SharedPackingItemDraft(title: "Палатка", category: "camp"),
            SharedPackingItemDraft(title: "Спички", category: nil),
        ])
    }
}
