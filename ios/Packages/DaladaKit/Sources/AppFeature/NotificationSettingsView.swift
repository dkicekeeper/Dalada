import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

/// Уведомления (из настроек профиля): разрешение системы, виды уведомлений и «тихие часы».
/// Переключатели меняются сразу; если сервер не принял — возвращаются к сохранённым.
struct NotificationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var settings = NotificationSettings()
    @State private var error: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        // DesignKit 8.0.0: стеклянные секции на странице (до этого List).
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                NotificationsSection()

                if session.profile != nil {
                    FormSection(
                        header: String(localized: "notifications.section.people"),
                        footer: String(localized: "notifications.people.footer")
                    ) {
                        toggleRow("notifications.kind.replies", \.replies)
                        toggleRow("notifications.kind.friendRequests", \.friendRequests)
                        toggleRow("notifications.kind.comments", \.comments)
                        toggleRow("notifications.kind.friendPosts", \.friendPosts)
                        toggleRow("notifications.kind.tripTags", \.tripTags)
                        toggleRow("notifications.kind.reactions", \.reactions)
                        toggleRow("notifications.kind.liveShare", \.liveShare)
                    }

                    FormSection(
                        header: String(localized: "notifications.section.places"),
                        footer: String(localized: "notifications.places.footer")
                    ) {
                        toggleRow("notifications.kind.bans", \.bans)
                        toggleRow("notifications.kind.placeActivity", \.placeActivity)
                        toggleRow("notifications.kind.steward", \.steward)
                    }

                    FormSection(
                        header: String(localized: "notifications.section.reminders"),
                        footer: String(localized: "notifications.reminders.footer")
                    ) {
                        toggleRow("notifications.kind.streak", \.streak)
                    }

                    FormSection(footer: quietFooter) {
                        UniversalRow(String(localized: "notifications.quiet.toggle"), accessory: .toggle(quietBinding))
                        if settings.quietHours != nil {
                            UniversalRow(
                                String(localized: "notifications.quiet.from"),
                                accessory: .menu(hourBinding(\.from), options: hourOptions)
                            )
                            UniversalRow(
                                String(localized: "notifications.quiet.to"),
                                accessory: .menu(hourBinding(\.to), options: hourOptions)
                            )
                        }
                    }

                    if let error {
                        InlineStatusText(message: error, type: .error)
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("notifications.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let saved = session.profile?.notificationSettings {
                settings = saved
            }
        }
    }

    private var hourOptions: [(label: String, value: Int)] {
        (0..<24).map { (label: Self.hourLabel($0), value: $0) }
    }

    private var quietFooter: String {
        if let quiet = settings.quietHours, quiet.from == quiet.to {
            String(localized: "notifications.quiet.same")
        } else {
            String(localized: "notifications.quiet.footer")
        }
    }

    private func toggleRow(_ title: LocalizedStringResource, _ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> some View {
        UniversalRow(String(localized: title), accessory: .toggle(binding(keyPath)))
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { isOn in
                settings[keyPath: keyPath] = isOn
                save()
            }
        )
    }

    private var quietBinding: Binding<Bool> {
        Binding(
            get: { settings.quietHours != nil },
            set: { isOn in
                settings.quietHours = isOn ? .default : nil
                save()
            }
        )
    }

    private func hourBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Int> {
        Binding(
            get: { settings.quietHours?[keyPath: keyPath] ?? QuietHours.default[keyPath: keyPath] },
            set: { hour in
                settings.quietHours?[keyPath: keyPath] = hour
                save()
            }
        )
    }

    /// Частые изменения (колесо часов) склеиваются: уходит последнее состояние.
    private func save() {
        let wanted = settings
        error = nil
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            let failure = await session.updateNotificationSettings(wanted)
            if Task.isCancelled { return }
            error = failure
            if failure != nil, let saved = session.profile?.notificationSettings {
                settings = saved
            }
        }
    }

    /// «22:00» или «10 PM» — как принято в языке и настройках телефона.
    static func hourLabel(_ hour: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)) ?? .now
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
    }
}
