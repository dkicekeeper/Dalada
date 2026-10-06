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

    /// Кэш без сети пишет и читает обычным `JSONEncoder` / `JSONDecoder`.
    @Test func roundTripsForCache() throws {
        let summary = SharedPackingSummary(
            id: UUID(), ownerID: UUID(), ownerUsername: "arman", ownerDisplayName: nil, title: "Капшагай",
            tripDate: CalendarDay(year: 2026, month: 10, day: 12), membersCount: 2, itemsCount: 3, doneCount: 1,
            isOwn: true, updatedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let item = SharedPackingItem(id: UUID(), title: "Палатка", category: "camp", position: 1, assigneeID: UUID(), done: true, createdBy: nil)
        let member = SharedPackingMember(userID: UUID(), username: nil, displayName: "Арман", avatarPath: nil, isOwner: true)
        #expect(try JSONDecoder().decode([SharedPackingSummary].self, from: JSONEncoder().encode([summary])) == [summary])
        #expect(try JSONDecoder().decode([SharedPackingItem].self, from: JSONEncoder().encode([item])) == [item])
        #expect(try JSONDecoder().decode([SharedPackingMember].self, from: JSONEncoder().encode([member])) == [member])
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
