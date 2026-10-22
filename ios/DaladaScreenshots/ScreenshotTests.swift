import XCTest

/// Скриншоты для App Store (workflow Screenshots, docs/05-release/README.md#скриншоты).
///
/// Запускает приложение под демо-аккаунтом (вход сам, в отладочной сборке — `SessionStore.start`) и
/// снимает экраны; каждый снимок — вложение с именем экрана в результатах теста. Окружение — от
/// xcodebuild через `TEST_RUNNER_…`: `SCREENSHOT_LANGUAGE` (ru, en), `SCREENSHOT_EMAIL`,
/// `SCREENSHOT_PASSWORD`. Если экран не нашёлся, тест его пропускает и снимает остальные.
final class ScreenshotTests: XCTestCase {
    /// Асылколь у Капшагая — место редакции с фото (CC BY 3.0, подпись — в рамке скриншота).
    private static let placeLink = URL(string: "dalada://place/861c15be-de92-49e9-80b8-c0e6fd4d92b8")!

    private var app: XCUIApplication!

    @MainActor
    func testAppStoreScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["SCREENSHOT_LANGUAGE"] ?? "ru"
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_KZ" : "en_KZ",
            // Знакомство с приложением и с кнопками карты — уже пройдены.
            "-intro.completed", "YES",
            "-map.tourSeen", "YES",
        ]
        app.launchEnvironment["DALADA_SCREENSHOT_EMAIL"] = environment["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["DALADA_SCREENSHOT_PASSWORD"] = environment["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        // Вход и первая загрузка.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Нет панели вкладок")
        pause(12)

        tab(1)
        allowLocation(timeout: 10)
        // Карта как при запуске — Алматинская область: много мест и зоны запретов. «Где я» (масштаб
        // 13) показывает Капшагай так близко, что ни одно место не попадает в кадр, а отдалять жестом
        // нельзя: щипок задевает панель вкладок, касание двумя пальцами XCUITest не выполняет.
        pause(20)
        snap("01-map")

        app.open(Self.placeLink)
        pause(6)
        expandSheet()
        pause(4)
        snap("02-place")
        closeSheet()

        tab(2)
        pause(8)
        snap("03-places")

        tab(4)
        pause(8)
        snap("04-profile")
        app.swipeUp()
        pause(4)
        // Первая своя поездка из раздела профиля, если есть.
        let trip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "ru" ? "км" : "km")).firstMatch
        if trip.exists && trip.isHittable {
            trip.tap()
            pause(8)
            snap("06-trip")
            app.navigationBars.buttons.element(boundBy: 0).tapIfPresent()
            pause(3)
        }
        // «Ваши места видите только вы» — свои места с пометкой «Только я».
        app.buttons[language == "ru" ? "Мои места" : "My places"].tapIfPresent()
        pause(4)
        snap("05-profile-content")

        tab(3)
        pause(6)
        snap("07-lifehacks")
        // «Главная» (08-home) — когда будет витринный аккаунт с друзьями: у демо-аккаунта в ленте
        // только свои записи, а подпись обещает друзей.
    }

    // MARK: - Помощники

    private func tab(_ index: Int) {
        let buttons = app.tabBars.firstMatch.buttons
        guard buttons.count > index else { return }
        buttons.element(boundBy: index).tap()
    }

    /// Лист (карточка места) — во весь экран: тянем от верха листа (на половине экрана) вверх.
    private func expandSheet() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// Лист (карточка места) закрываем жестом вниз.
    private func closeSheet() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        pause(2)
    }

    /// Системный вопрос о геопозиции — «При использовании приложения». Окно рисует SpringBoard на
    /// языке симулятора, поэтому ищем кнопку по-английски и по-русски.
    private func allowLocation(timeout: TimeInterval) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        let allow = alert.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "While Using", "использовании"
        )).firstMatch
        if allow.exists {
            allow.tap()
        } else {
            alert.buttons.element(boundBy: 1).tapIfPresent()
        }
        pause(2)
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    private func snap(_ name: String) {
        // Системное окно поверх приложения на витрину не годится.
        allowLocation(timeout: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func tapIfPresent() {
        if exists && isHittable { tap() }
    }
}
