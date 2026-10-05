import Foundation

/// Через сколько минут стоянки запись встаёт на автопаузу. Хранится на телефоне.
public enum AutoPauseSetting {
    public static let storageKey = "trip.autoPauseMinutes"
    /// Варианты в настройках; 0 — выключена.
    public static let options = [0, 5, 10, 20]
    public static let defaultMinutes = 10

    /// Задержка по сохранённому значению (`nil` в хранилище — по умолчанию).
    public static func delay(minutes: Int?) -> TimeInterval {
        TimeInterval(minutes ?? defaultMinutes) * 60
    }
}

/// Автопауза на долгих стоянках: GPS «гуляет» на 10–20 м, и стоя на берегу часами запись набирает
/// метры, которых не было. Стоим в круге `radius` дольше `delay` — пауза: точки не пишутся. Ушли из
/// круга (с учётом погрешности) — запись продолжается, линия трека не рвётся.
public struct AutoPauseDetector: Sendable {
    public enum Event: Equatable, Sendable {
        case none
        case paused
        case resumed
    }

    /// Радиус стоянки, м.
    public static let radius = 30.0
    /// Точки грубее не учитываем, м.
    public static let maxAccuracy = 50.0

    /// Задержка до паузы; 0 — автопауза выключена.
    public var delay: TimeInterval
    public private(set) var isPaused = false
    /// Центр стоянки: первая точка в текущем круге.
    public private(set) var anchor: TrackPoint?

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    public var isEnabled: Bool { delay > 0 }

    /// Начать заново: после ручной паузы, продолжения, восстановления записи.
    public mutating func reset() {
        isPaused = false
        anchor = nil
    }

    /// Новая точка GPS (до фильтра трека).
    public mutating func observe(_ point: TrackPoint) -> Event {
        guard isEnabled else { return .none }
        guard point.horizontalAccuracy >= 0, point.horizontalAccuracy <= Self.maxAccuracy else {
            return tick(now: point.timestamp)
        }
        guard let anchor else {
            self.anchor = point
            return .none
        }
        let distance = anchor.coordinate.distance(to: point.coordinate)
        if isPaused {
            // Уверенно вне круга: даже с погрешностью точка дальше радиуса.
            guard distance - point.horizontalAccuracy > Self.radius else { return .none }
            isPaused = false
            self.anchor = point
            return .resumed
        }
        if distance > Self.radius {
            self.anchor = point
            return .none
        }
        return tick(now: point.timestamp)
    }

    /// Время идёт без новых точек (телефон стоит — GPS может молчать).
    public mutating func tick(now: Date) -> Event {
        guard isEnabled, !isPaused, let anchor else { return .none }
        guard now.timeIntervalSince(anchor.timestamp) >= delay else { return .none }
        isPaused = true
        return .paused
    }
}
