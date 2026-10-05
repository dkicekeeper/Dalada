import Backend
import Charts
import DaladaCore
import DesignComponents
import DesignTokens
import Persistence
import SwiftUI

// MARK: - Загрузка

/// Погода у точки: свежий сохранённый прогноз, иначе — из сети (Open-Meteo), без сети — сохранённый,
/// если он не слишком старый. Сохраняется общим для всех ключом — координаты округлены до 0,01°.
struct PlaceWeatherLoader {
    let cache: CacheStore

    func load(
        at point: GeoPoint,
        maxAge: TimeInterval = 30 * 60,
        maxStale: TimeInterval = 24 * 3600
    ) async -> PlaceForecast? {
        let key = CacheKey.weather(point)
        let saved = try? await cache.load(PlaceForecast.self, for: key)
        if let saved, saved.isFresh(at: .now, maxAge: maxAge) {
            return saved
        }
        if let fresh = try? await WeatherClient().forecast(at: point) {
            try? await cache.save(fresh, for: key)
            return fresh
        }
        if let saved, Date.now.timeIntervalSince(saved.fetchedAt) < maxStale {
            return saved
        }
        return nil
    }
}

// MARK: - Подписи

/// Подписи погоды. Давление — в мм рт. ст., как привыкли рыбаки; в английском интерфейсе — в гПа.
enum WeatherText {
    static var usesMillimeters: Bool {
        Bundle.main.preferredLocalizations.first != "en"
    }

    static func temperature(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)°" }
        if rounded < 0 { return "−\(-rounded)°" }
        return "0°"
    }

    static func compass(_ degrees: Double) -> String {
        let key = WeatherUnits.compassKeys[WeatherUnits.compassSector(degrees)]
        return String(localized: String.LocalizationValue("weather.dir." + key))
    }

    /// «3 м/с СВ».
    static func wind(_ snapshot: WeatherSnapshot) -> String? {
        guard let speed = snapshot.windSpeed else { return nil }
        let value = String(Int(speed.rounded()))
        var text = String(localized: "weather.windSpeed \(value)")
        if let direction = snapshot.windDirection {
            text += " " + compass(direction)
        }
        return text
    }

    /// Значение давления в единицах интерфейса — для графика.
    static func pressureValue(_ hectopascals: Double) -> Double {
        usesMillimeters ? hectopascals * 0.750_062 : hectopascals
    }

    /// «689 мм рт. ст.» или коротко «689 мм».
    static func pressure(_ hectopascals: Double, short: Bool = false) -> String {
        guard usesMillimeters else {
            return String(localized: "weather.pressure.hpa \(Int(hectopascals.rounded()))")
        }
        let millimeters = WeatherUnits.millimetersOfMercury(hectopascals)
        return short
            ? String(localized: "weather.pressureShort.mmhg \(millimeters)")
            : String(localized: "weather.pressure.mmhg \(millimeters)")
    }

    /// «−3 мм» за сутки.
    static func pressureDelta(_ hectopascals: Double) -> String {
        let value = Int(pressureValue(hectopascals).rounded())
        let signed = value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "0"
        return usesMillimeters
            ? String(localized: "weather.pressureDelta.mmhg \(signed)")
            : String(localized: "weather.pressureDelta.hpa \(signed)")
    }

    /// «+18° · 3 м/с СВ · 689 мм» — для строки погоды и отчёта.
    static func summary(_ snapshot: WeatherSnapshot) -> String? {
        let parts = [
            snapshot.temperature.map(temperature),
            wind(snapshot),
            snapshot.pressure.map { pressure($0, short: true) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Строка в карточке места

/// Погода у места одной строкой: значок, температура, ветер, давление и куда оно идёт. Нажатие —
/// подробно. Без сети — сохранённый прогноз (до суток); нет и его — строки нет.
struct PlaceWeatherRow: View {
    let coordinate: GeoPoint
    let environment: AppEnvironment

    @State private var forecast: PlaceForecast?
    @State private var showsDetails = false

    var body: some View {
        Group {
            if let forecast {
                Button {
                    showsDetails = true
                } label: {
                    row(forecast)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsDetails) {
                    PlaceWeatherSheet(forecast: forecast)
                }
            }
        }
        .task(id: coordinate) {
            forecast = await PlaceWeatherLoader(cache: environment.cache).load(at: coordinate)
        }
    }

    private func row(_ forecast: PlaceForecast) -> some View {
        let current = forecast.current
        let trend = forecast.pressureTrend(at: .now)
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: WeatherKind(code: current.code)?.systemImage ?? "thermometer.medium")
                .foregroundStyle(AppColors.accent)
            if let temperature = current.temperature {
                Text(verbatim: WeatherText.temperature(temperature))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
            }
            Text(verbatim: details(current))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            if let trend {
                Image(systemName: trend.systemImage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel(Text(LocalizedStringKey(trend.titleKey)))
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .cardContentPadding()
        .cardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("weather.title"))
    }

    private func details(_ current: WeatherSnapshot) -> String {
        [WeatherText.wind(current), current.pressure.map { WeatherText.pressure($0, short: true) }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Подробно

/// Погода у места подробно: сейчас, давление за 3 дня и прогноз (график), дни, восход и закат.
/// Время — местное для места.
struct PlaceWeatherSheet: View {
    let forecast: PlaceForecast

    @Environment(\.dismiss) private var dismiss

    private var timeZone: TimeZone {
        TimeZone(secondsFromGMT: forecast.utcOffsetSeconds) ?? .current
    }

    var body: some View {
        NavigationStack {
            List {
                currentSection
                if forecast.pressure.count > 1 {
                    Section("weather.pressure") {
                        pressureChart
                    }
                }
                daysSection
                sunSection
                Section {
                } footer: {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("weather.updated \(time(forecast.fetchedAt, zone: .current))")
                        Link(destination: OpenMeteo.attributionURL) {
                            Text("weather.attribution")
                        }
                    }
                }
            }
            .navigationTitle("weather.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var currentSection: some View {
        let current = forecast.current
        let kind = WeatherKind(code: current.code)
        return Section("weather.now") {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: kind?.systemImage ?? "thermometer.medium")
                    .font(.largeTitle)
                    .foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    if let temperature = current.temperature {
                        Text(verbatim: WeatherText.temperature(temperature))
                            .font(AppTypography.h2)
                    }
                    if let kind {
                        Text(LocalizedStringKey(kind.titleKey))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            if let wind = WeatherText.wind(current) {
                LabeledContent("weather.wind") {
                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(verbatim: wind)
                        if let gusts = current.windGusts, gusts >= (current.windSpeed ?? 0) + 2 {
                            Text("weather.gusts \(String(Int(gusts.rounded())))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
            if let pressure = current.pressure {
                LabeledContent("weather.pressure") {
                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(verbatim: WeatherText.pressure(pressure))
                        if let delta = forecast.pressureChange(before: .now) {
                            let trend = PressureTrend(delta: delta)
                            Label {
                                Text("weather.trend.day \(WeatherText.pressureDelta(delta)) \(String(localized: String.LocalizationValue(trend.titleKey)))")
                            } icon: {
                                Image(systemName: trend.systemImage)
                            }
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    /// Давление за 3 дня назад и прогноз; линия «сейчас».
    private var pressureChart: some View {
        Chart {
            ForEach(forecast.pressure, id: \.time) { point in
                LineMark(
                    x: .value("time", point.time),
                    y: .value("pressure", WeatherText.pressureValue(point.pressure))
                )
                .foregroundStyle(AppColors.accent)
            }
            RuleMark(x: .value("now", Date.now))
                .foregroundStyle(AppColors.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 160)
        .accessibilityLabel(Text("weather.pressure"))
    }

    private var daysSection: some View {
        let days = forecast.upcomingDays(from: .now)
        return Section("weather.forecast") {
            ForEach(days) { day in
                HStack(spacing: AppSpacing.sm) {
                    Text(verbatim: dayTitle(day.date))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let kind = WeatherKind(code: day.code) {
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(AppColors.accent)
                            .accessibilityLabel(Text(LocalizedStringKey(kind.titleKey)))
                    }
                    if let low = day.temperatureMin, let high = day.temperatureMax {
                        Text(verbatim: WeatherText.temperature(low) + " … " + WeatherText.temperature(high))
                            .monospacedDigit()
                    }
                    if let wind = day.windMax {
                        Text("weather.windSpeed \(String(Int(wind.rounded())))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .font(AppTypography.bodySmall)
                if let precipitation = day.precipitation, precipitation >= 0.5 {
                    Text("weather.precipitation \(precipitation.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var sunSection: some View {
        if let today = forecast.upcomingDays(from: .now, count: 1).first, today.sunrise != nil || today.sunset != nil {
            Section("weather.sun") {
                if let sunrise = today.sunrise {
                    LabeledContent("weather.sunrise") {
                        Text(verbatim: time(sunrise, zone: timeZone))
                    }
                }
                if let sunset = today.sunset {
                    LabeledContent("weather.sunset") {
                        Text(verbatim: time(sunset, zone: timeZone))
                    }
                }
            }
        }
    }

    private func time(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    private func dayTitle(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.wide).day().month(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
