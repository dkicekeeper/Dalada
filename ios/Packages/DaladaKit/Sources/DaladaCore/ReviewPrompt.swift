import Foundation

/// Когда попросить оценку в App Store (docs/05-release/promotion.md, этап 0). Только после удачи:
/// сохранённый отчёт или настоящая поездка. Нужно три таких момента, не раньше трёх дней с первого
/// запуска, один раз на версию и не чаще раза в 120 дней. Покажет ли iOS окно — решает она сама
/// (не больше трёх раз в год), поэтому лишний вызов не страшен, а редкий — бережёт впечатление.
public enum ReviewPromptPolicy {
    public static let minimumDays = 3
    public static let minimumMoments = 3
    public static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    /// Что помним между запусками (UserDefaults, JSON).
    public struct State: Codable, Equatable, Sendable {
        /// Первый запуск с этой логикой — точнее установки iOS не скажет.
        public var firstSeen: Date?
        /// Удачные моменты с прошлого запроса.
        public var moments: Int
        public var lastPromptVersion: String?
        public var lastPromptAt: Date?

        public init(firstSeen: Date? = nil, moments: Int = 0, lastPromptVersion: String? = nil, lastPromptAt: Date? = nil) {
            self.firstSeen = firstSeen
            self.moments = moments
            self.lastPromptVersion = lastPromptVersion
            self.lastPromptAt = lastPromptAt
        }
    }

    /// Запуск приложения: запомнить первый.
    public static func noteLaunch(_ state: inout State, now: Date) {
        if state.firstSeen == nil { state.firstSeen = now }
    }

    /// Удачный момент: отчёт сохранён, поездка завершена.
    public static func noteMoment(_ state: inout State, now: Date) {
        noteLaunch(&state, now: now)
        state.moments += 1
    }

    /// Пора ли просить оценку в версии `version`.
    public static func shouldPrompt(_ state: State, now: Date, version: String) -> Bool {
        guard let firstSeen = state.firstSeen,
              now.timeIntervalSince(firstSeen) >= TimeInterval(minimumDays) * 24 * 60 * 60,
              state.moments >= minimumMoments,
              state.lastPromptVersion != version
        else { return false }
        if let last = state.lastPromptAt, now.timeIntervalSince(last) < cooldown { return false }
        return true
    }

    /// Запрос показан (или отдан iOS): следующий — в другой версии и после новых трёх моментов.
    public static func notePrompted(_ state: inout State, now: Date, version: String) {
        state.moments = 0
        state.lastPromptVersion = version
        state.lastPromptAt = now
    }
}
