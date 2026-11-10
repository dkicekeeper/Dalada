import DaladaCore
import Foundation
import StoreKit
import UIKit

/// Просит оценку в App Store в удачный момент — когда, решает `ReviewPromptPolicy` (DaladaCore).
/// Окно рисует сама iOS поверх любого экрана; лист про уведомления не перебиваем.
@MainActor
final class ReviewRequester {
    static let shared = ReviewRequester()

    private static let key = "review.prompt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Из `AppBootstrap.configure()`: запомнить первый запуск.
    func noteLaunch() {
        var state = load()
        ReviewPromptPolicy.noteLaunch(&state, now: Date())
        save(state)
    }

    /// Удачный момент: отчёт сохранён, настоящая поездка завершена. Если пора — попросить оценку,
    /// когда закроется форма.
    func noteSuccess() async {
        var state = load()
        let now = Date()
        ReviewPromptPolicy.noteMoment(&state, now: now)
        save(state)
        guard ReviewPromptPolicy.shouldPrompt(state, now: now, version: Self.version) else { return }
        // Даём закрыться форме; лист про уведомления и предложение поделиться появляются через 0,7 с —
        // им уступаем, момент не теряется: попросим после следующего отчёта.
        try? await Task.sleep(for: .milliseconds(1500))
        guard !NotificationPrimer.shared.isShowing, !ShareOffer.shared.isShowing,
              let scene = Self.activeScene() else { return }
        AppStore.requestReview(in: scene)
        var shown = load()
        ReviewPromptPolicy.notePrompted(&shown, now: Date(), version: Self.version)
        save(shown)
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func load() -> ReviewPromptPolicy.State {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(ReviewPromptPolicy.State.self, from: data)
        else { return ReviewPromptPolicy.State() }
        return state
    }

    private func save(_ state: ReviewPromptPolicy.State) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key)
    }
}
