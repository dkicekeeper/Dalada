import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

extension Notification.Name {
    /// Свою поездку изменили или удалили — спискам поездок пора обновиться. `object` — id поездки.
    static let daladaTripChanged = Notification.Name("dalada.tripChanged")
}

/// Правка своей поездки: название, вид отдыха, заметка. Трек и цифры не меняются.
struct TripEditView: View {
    let trip: TripDetails
    let environment: AppEnvironment
    let onSaved: @MainActor (TripDetails) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var activity: TripActivity
    @State private var note: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(trip: TripDetails, environment: AppEnvironment, onSaved: @escaping @MainActor (TripDetails) -> Void) {
        self.trip = trip
        self.environment = environment
        self.onSaved = onSaved
        _title = State(initialValue: trip.summary.title)
        _activity = State(initialValue: trip.summary.activity)
        _note = State(initialValue: trip.summary.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("trip.finish.name") {
                    TextField("trip.finish.name", text: $title)
                    Picker("trip.finish.activity", selection: $activity) {
                        ForEach(TripActivity.allCases) { item in
                            Label(LocalizedStringKey(item.titleKey), systemImage: item.systemImage).tag(item)
                        }
                    }
                }
                Section("checkin.form.note") {
                    TextField("trip.finish.notePlaceholder", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            .navigationTitle("trip.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        (1...100).contains(trimmedTitle.count) && note.count <= 2000
    }

    private func save() async {
        guard let backend = environment.backend else {
            saveError = String(localized: "own.error.offline")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.updateTrip(trip.summary.id, title: trimmedTitle, activity: activity, note: note)
            onSaved(trip.with(title: trimmedTitle, activity: activity, note: note))
            NotificationCenter.default.post(name: .daladaTripChanged, object: trip.summary.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
