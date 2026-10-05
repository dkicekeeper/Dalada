import Foundation
import Testing
@testable import DaladaCore

@Suite("Автопауза")
struct AutoPauseTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Точка в `meters` метрах к востоку от начала (широта 43.5) через `seconds` секунд.
    private func point(_ meters: Double, after seconds: TimeInterval, accuracy: Double = 8) -> TrackPoint {
        // 1° долготы на широте 43.5 ≈ 80 700 м.
        TrackPoint(
            latitude: 43.5,
            longitude: 77.0 + meters / 80_700,
            horizontalAccuracy: accuracy,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    @Test func pausesAfterStandingStill() {
        var detector = AutoPauseDetector(delay: 600)
        #expect(detector.observe(point(0, after: 0)) == .none)
        // GPS «гуляет» на 10–20 м — всё ещё стоянка.
        #expect(detector.observe(point(15, after: 120)) == .none)
        #expect(detector.observe(point(-12, after: 400)) == .none)
        #expect(detector.observe(point(8, after: 600)) == .paused)
        #expect(detector.isPaused)
    }

    @Test func pausesOnTickWhenGPSIsSilent() {
        var detector = AutoPauseDetector(delay: 300)
        _ = detector.observe(point(0, after: 0))
        #expect(detector.tick(now: start.addingTimeInterval(299)) == .none)
        #expect(detector.tick(now: start.addingTimeInterval(300)) == .paused)
        // Повторно паузу не объявляет.
        #expect(detector.tick(now: start.addingTimeInterval(900)) == .none)
    }

    @Test func walkingNeverPauses() {
        var detector = AutoPauseDetector(delay: 300)
        for step in 0..<60 {
            // 1,2 м/с — каждые 10 секунд 12 м, за 10 минут — 720 м.
            #expect(detector.observe(point(Double(step) * 12, after: Double(step) * 10)) == .none)
        }
        #expect(!detector.isPaused)
    }

    @Test func resumesOnlyWhenSurelyOutside() {
        var detector = AutoPauseDetector(delay: 60)
        _ = detector.observe(point(0, after: 0))
        #expect(detector.observe(point(5, after: 60)) == .paused)
        // 40 м, но погрешность 20 м — может быть ещё на месте.
        #expect(detector.observe(point(40, after: 120, accuracy: 20)) == .none)
        #expect(detector.isPaused)
        // 45 м при погрешности 10 м — точно ушёл.
        #expect(detector.observe(point(45, after: 130, accuracy: 10)) == .resumed)
        #expect(!detector.isPaused)
        // Новая стоянка считается от новой точки.
        #expect(detector.tick(now: start.addingTimeInterval(180)) == .none)
        #expect(detector.tick(now: start.addingTimeInterval(190)) == .paused)
    }

    @Test func roughPointsDoNotMoveTheStop() {
        var detector = AutoPauseDetector(delay: 60)
        _ = detector.observe(point(0, after: 0))
        _ = detector.observe(point(5, after: 60))
        // Грубая точка далеко — выброс GPS, не уход.
        #expect(detector.observe(point(500, after: 70, accuracy: 120)) == .none)
        #expect(detector.isPaused)
    }

    @Test func disabledDoesNothing() {
        var detector = AutoPauseDetector(delay: 0)
        _ = detector.observe(point(0, after: 0))
        #expect(detector.observe(point(1, after: 10_000)) == .none)
        #expect(detector.tick(now: start.addingTimeInterval(20_000)) == .none)
        #expect(!detector.isEnabled)
    }

    @Test func resetForgetsTheStop() {
        var detector = AutoPauseDetector(delay: 60)
        _ = detector.observe(point(0, after: 0))
        _ = detector.observe(point(5, after: 60))
        detector.reset()
        #expect(!detector.isPaused)
        #expect(detector.anchor == nil)
        #expect(detector.tick(now: start.addingTimeInterval(1000)) == .none)
    }

    @Test func settingDefaultsToTenMinutes() {
        #expect(AutoPauseSetting.delay(minutes: nil) == 600)
        #expect(AutoPauseSetting.delay(minutes: 0) == 0)
        #expect(AutoPauseSetting.delay(minutes: 20) == 1200)
        #expect(AutoPauseSetting.options.contains(AutoPauseSetting.defaultMinutes))
    }
}
