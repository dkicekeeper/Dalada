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
            // Знакомство и подсказка о долгом нажатии — уже пройдены.
            "-intro.completed", "YES",
            "-map.longPressHintSeen", "YES",
        ]
        app.launchEnvironment["DALADA_SCREENSHOT_EMAIL"] = environment["SCREENSHOT_EMAIL"] ?? ""
        app.launchEnvironment["DALADA_SCREENSHOT_PASSWORD"] = environment["SCREENSHOT_PASSWORD"] ?? ""
        app.launch()

        // Вход и первая загрузка.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Нет панели вкладок")
        pause(12)

        tab(1)
        pause(10)
        snap("01-map")

        app.open(Self.placeLink)
        pause(8)
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
        snap("05-profile-content")
        // Первая своя поездка из раздела профиля, если есть.
        let trip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "ru" ? "км" : "km")).firstMatch
        if trip.exists && trip.isHittable {
            trip.tap()
            pause(8)
            snap("06-trip")
            app.navigationBars.buttons.element(boundBy: 0).tapIfPresent()
        }

        tab(3)
        pause(6)
        snap("07-lifehacks")

        tab(0)
        pause(8)
        snap("08-home")
    }

    // MARK: - Помощники

    private func tab(_ index: Int) {
        let buttons = app.tabBars.firstMatch.buttons
        guard buttons.count > index else { return }
        buttons.element(boundBy: index).tap()
    }

    /// Лист (карточка места) закрываем жестом вниз.
    private func closeSheet() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        pause(2)
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    private func snap(_ name: String) {
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
