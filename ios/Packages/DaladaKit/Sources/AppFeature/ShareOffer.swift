import DaladaCore
import DesignComponents
import Foundation
import SwiftUI
import UIKit

/// Предложить картинку для Stories в момент гордости (docs/05-release/promotion.md, этап 0, п. 0.4):
/// после настоящей поездки — вопросом (`PromptSheet` из DesignKit), когда — решает `SharePromptPolicy`;
/// после нового личного рекорда — кнопкой «Поделиться рекордом» в самом поздравлении.
///
/// Листы показываются поверх самого верхнего экрана (UIKit), как `NotificationPrimer`: форма поездки и
/// экран записи к этому времени уже закрываются, а SwiftUI из корня так не умеет.
@MainActor
final class ShareOffer {
    static let shared = ShareOffer()

    private static let key = "share.offer"
    private let defaults: UserDefaults
    private weak var presented: UIViewController?
    /// Лист вот-вот появится — запрос оценки и праймер уведомлений ждут.
    private var isPending = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Открыт вопрос или лист картинки — другие окна (оценка, уведомления) не перебивают.
    var isShowing: Bool { isPending || presented != nil }

    /// Настоящая поездка завершена: если пора — спросить, не поделиться ли картинкой.
    func offerTrip(id: UUID, isPublic: Bool, environment: AppEnvironment) async {
        var state = load()
        guard !isShowing, SharePromptPolicy.shouldOffer(state, now: Date()) else { return }
        isPending = true
        defer { isPending = false }
        // Даём закрыться форме поездки и экрану записи.
        try? await Task.sleep(for: .milliseconds(700))
        guard presented == nil, let top = Self.topViewController() else { return }
        SharePromptPolicy.noteOffered(&state, now: Date())
        save(state)
        let host = UIHostingController(rootView: PromptSheet(
            systemImage: "square.and.arrow.up",
            title: String(localized: "share.offer.trip.title"),
            message: String(localized: "share.offer.trip.body"),
            primaryTitle: String(localized: "share.title"),
            secondaryTitle: String(localized: "share.offer.later"),
            detent: nil,
            dismissesOnAnswer: false,
            onPrimary: { [weak self] in
                await MainActor.run { self?.answer(shared: true, tripID: id, isPublic: isPublic, environment: environment) }
            },
            onSecondary: { [weak self] in self?.answer(shared: false, tripID: id, isPublic: isPublic, environment: environment) }
        ))
        host.isModalInPresentation = true
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = false
        }
        presented = host
        top.present(host, animated: true)
    }

    /// «Поделиться рекордом» в поздравлении: сразу лист картинки улова. Окружение — из формы отчёта.
    func shareCatch(id: UUID, isPublic: Bool, session: SessionStore, species: SpeciesStore) async {
        guard !isShowing else { return }
        isPending = true
        defer { isPending = false }
        // Даём закрыться поздравлению и форме отчёта.
        try? await Task.sleep(for: .milliseconds(700))
        guard presented == nil, let top = Self.topViewController() else { return }
        let host = UIHostingController(rootView:
            CatchShareCardSheet(catchID: id, isPublic: isPublic, waitsForUpload: true)
                .environment(session)
                .environment(species)
        )
        presented = host
        top.present(host, animated: true)
    }

    private func answer(shared: Bool, tripID: UUID, isPublic: Bool, environment: AppEnvironment) {
        var state = load()
        SharePromptPolicy.noteAnswer(&state, shared: shared)
        save(state)
        let prompt = presented
        presented = nil
        guard shared else {
            prompt?.dismiss(animated: true)
            return
        }
        // Вопрос закрывается — на его месте лист картинки.
        prompt?.dismiss(animated: true) { [weak self] in
            guard let self, let top = Self.topViewController() else { return }
            let host = UIHostingController(rootView:
                TripShareCardSheet(tripID: tripID, environment: environment, isPublic: isPublic, waitsForUpload: true)
            )
            self.presented = host
            top.present(host, animated: true)
        }
    }

    private func load() -> SharePromptPolicy.State {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(SharePromptPolicy.State.self, from: data)
        else { return SharePromptPolicy.State() }
        return state
    }

    private func save(_ state: SharePromptPolicy.State) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.key)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.first?.keyWindow,
            var top = window.rootViewController
        else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
