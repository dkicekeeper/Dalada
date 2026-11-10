import Foundation

/// Когда после поездки предложить картинку для Stories (docs/05-release/promotion.md, этап 0, п. 0.4):
/// момент гордости — лучший для шаринга, но навязываться нельзя. Не чаще раза в три дня; три «Не сейчас»
/// подряд — больше не предлагаем (кнопка на странице поездки остаётся). Новый рекорд предлагает
/// поделиться в самом поздравлении — без этого правила: рекорды редкие.
public enum SharePromptPolicy {
    public static let cooldown: TimeInterval = 3 * 24 * 60 * 60
    public static let maximumDeclines = 3

    /// Что помним между запусками (UserDefaults, JSON).
    public struct State: Codable, Equatable, Sendable {
        public var lastOfferedAt: Date?
        /// «Не сейчас» подряд; «Поделиться» обнуляет.
        public var declines: Int

        public init(lastOfferedAt: Date? = nil, declines: Int = 0) {
            self.lastOfferedAt = lastOfferedAt
            self.declines = declines
        }
    }

    /// Пора ли предложить поделиться.
    public static func shouldOffer(_ state: State, now: Date) -> Bool {
        guard state.declines < maximumDeclines else { return false }
        if let last = state.lastOfferedAt, now.timeIntervalSince(last) < cooldown { return false }
        return true
    }

    /// Предложение показано.
    public static func noteOffered(_ state: inout State, now: Date) {
        state.lastOfferedAt = now
    }

    /// Ответ: поделился — счёт отказов с нуля, «Не сейчас» — плюс один.
    public static func noteAnswer(_ state: inout State, shared: Bool) {
        state.declines = shared ? 0 : state.declines + 1
    }
}
