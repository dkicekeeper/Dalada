import Foundation

/// Серия: недели подряд с поездкой или отчётом (`my_streak`). Зима и запрет там, где вы
/// отчитывались, серию не обрывают.
public struct Streak: Codable, Equatable, Sendable {
    public enum Freeze: String, Codable, Sendable {
        case winter
        case ban
    }

    public let currentWeeks: Int
    public let bestWeeks: Int
    /// На этой неделе уже был выезд.
    public let thisWeekDone: Bool
    /// Эта неделя заморожена — пропуск серию не оборвёт.
    public let freeze: Freeze?

    public init(currentWeeks: Int, bestWeeks: Int, thisWeekDone: Bool, freeze: Freeze? = nil) {
        self.currentWeeks = currentWeeks
        self.bestWeeks = bestWeeks
        self.thisWeekDone = thisWeekDone
        self.freeze = freeze
    }

    enum CodingKeys: String, CodingKey {
        case currentWeeks = "current_weeks"
        case bestWeeks = "best_weeks"
        case thisWeekDone = "this_week_done"
        case freeze = "freeze_reason"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentWeeks = try c.decode(Int.self, forKey: .currentWeeks)
        bestWeeks = try c.decode(Int.self, forKey: .bestWeeks)
        thisWeekDone = try c.decodeIfPresent(Bool.self, forKey: .thisWeekDone) ?? false
        // Незнакомая причина из новой версии сервера — без подписи, а не ошибка.
        freeze = try? c.decodeIfPresent(Freeze.self, forKey: .freeze)
    }

    /// Подсказка под серией (ключ строки).
    public var hintKey: String {
        if thisWeekDone { return "streak.hint.done" }
        switch freeze {
        case .winter: return "streak.hint.winter"
        case .ban: return "streak.hint.ban"
        case nil: return currentWeeks > 0 ? "streak.hint.keep" : "streak.hint.start"
        }
    }
}
