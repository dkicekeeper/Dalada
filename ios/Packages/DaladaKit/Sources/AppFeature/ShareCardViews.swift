import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import UIKit

// MARK: - Рамка картинки

extension ShareCard.Style {
    /// Цвета картинок Dalada: тёмный фон с бирюзовым акцентом — картинка одинаковая в светлой
    /// и тёмной теме.
    static let dalada = ShareCard.Style(
        top: Color(red: 0.06, green: 0.20, blue: 0.22),
        bottom: Color(red: 0.02, green: 0.05, blue: 0.07),
        accent: Color(red: 0.33, green: 0.85, blue: 0.78)
    )
}

/// Рамка картинки Dalada: `ShareCardFrame` из DesignKit — фон (фото во весь кадр или градиент),
/// подпись «Dalada» и адрес сайта внизу.
struct DaladaShareCardFrame<Content: View>: View {
    let format: ShareCard.Format
    var photo: UIImage?
    @ViewBuilder let content: Content

    var body: some View {
        ShareCardFrame(format: format, brand: "Dalada", site: ShareCardLink.siteLabel, photo: photo, style: .dalada) {
            content
        }
    }
}

// MARK: - Поездка

/// Картинка поездки: вид, название, дата, линия трека (без начала и конца), цифры.
struct TripShareCardView: View {
    let card: TripShareCard
    let format: ShareCard.Format

    var body: some View {
        DaladaShareCardFrame(format: format) {
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey(card.activity.titleKey), systemImage: card.activity.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCard.Style.dalada.accent)
                Text(verbatim: card.title)
                    .font(.system(size: format == .story ? 32 : 28, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(card.startedAt, format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 14))
                    .opacity(0.7)
            }

            track
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)

            HStack(alignment: .top, spacing: 12) {
                ShareCardStat(value: TripFormat.distance(Double(card.distanceM)), title: String(localized: "trip.stat.distance"))
                ShareCardStat(value: TripFormat.duration(Double(card.movingSeconds)), title: String(localized: "trip.stat.time"))
                if card.elevationGainM > 0 {
                    ShareCardStat(value: TripFormat.elevation(Double(card.elevationGainM)), title: String(localized: "trip.stat.elevation"))
                }
            }
        }
    }

    @ViewBuilder
    private var track: some View {
        let lines = TrackPreview.normalized(card.segments)
        if lines.isEmpty {
            Image(systemName: card.activity.systemImage)
                .font(.system(size: 96))
                .foregroundStyle(ShareCard.Style.dalada.accent.opacity(0.5))
        } else {
            ZStack {
                TrackLineShape(lines: lines, inset: 10)
                    .stroke(ShareCard.Style.dalada.accent.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                TrackLineShape(lines: lines, inset: 10)
                    .stroke(ShareCard.Style.dalada.accent, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Улов

/// Картинка улова: фото во весь кадр (если есть), вид, вес и длина, «отпущена», место и дата.
struct CatchShareCardView: View {
    let card: CatchShareCard
    let speciesName: String
    let photo: UIImage?
    let format: ShareCard.Format

    var body: some View {
        DaladaShareCardFrame(format: format, photo: photo) {
            Spacer(minLength: 0)
            if photo == nil {
                Image(systemName: "fish.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(ShareCard.Style.dalada.accent.opacity(0.85))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("share.catch.title")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCard.Style.dalada.accent)
                Text(verbatim: card.count > 1 ? "\(speciesName) ×\(card.count)" : speciesName)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let metrics {
                    Text(verbatim: metrics)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if card.released {
                    Label("catch.released", systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                Text(verbatim: details)
                    .font(.system(size: 14))
                    .opacity(0.75)
                    .lineLimit(2)
            }
        }
    }

    /// «2,4 кг · 56 см».
    private var metrics: String? {
        var parts: [String] = []
        if let grams = card.weightGrams {
            parts.append(Measurement(value: Double(grams) / 1000, unit: UnitMass.kilograms)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))))
        }
        if let millimeters = card.lengthMillimeters {
            parts.append(Measurement(value: Double(millimeters) / 10, unit: UnitLength.centimeters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «Капшагай · 2 октября 2026 г.» (место — только публичное).
    private var details: String {
        let date = card.at.formatted(.dateTime.day().month(.wide).year())
        return [card.placeName, date].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Место

/// Данные для картинки места: собираются из карточки места.
struct PlaceShareCard {
    let name: String
    let type: PlaceType
    let rating: Double?
    let reviewsCount: Int
    let photo: UIImage?
}

/// Картинка места: фото во весь кадр (если есть), тип, название, оценка.
struct PlaceShareCardView: View {
    let card: PlaceShareCard
    let format: ShareCard.Format

    var body: some View {
        DaladaShareCardFrame(format: format, photo: card.photo) {
            Spacer(minLength: 0)
            if card.photo == nil {
                Image(systemName: card.type.systemImage)
                    .font(.system(size: 110))
                    .foregroundStyle(ShareCard.Style.dalada.accent.opacity(0.85))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(card.type.titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShareCard.Style.dalada.accent)
                Text(verbatim: card.name)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let rating = card.rating, card.reviewsCount > 0 {
                    Label {
                        Text("share.place.rating \(rating.formatted(.number.precision(.fractionLength(1)))) \(card.reviewsCount)")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Кнопки

/// «Картинка для Stories» своей поездки (значок в панели страницы поездки).
struct TripShareCardButton: View {
    let tripID: UUID
    let environment: AppEnvironment
    /// Публичную поездку можно открыть в браузере — в сообщении ссылка на её страницу.
    var isPublic = false

    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .accessibilityLabel(Text("share.title"))
        }
        .sheet(isPresented: $showsSheet) {
            ShareCardSheet(
                previewTitle: "Dalada",
                load: { try? await environment.backend?.tripShareCard(tripID) },
                message: { card in
                    let link = isPublic ? WebLink.trip(tripID) : ShareCardLink.site
                    return String(localized: "share.message.trip \(card.title) \(link.absoluteString)")
                }
            ) { card, format in
                TripShareCardView(card: card, format: format)
            }
        }
    }
}

/// «Картинка для Stories» своего улова (кнопка в строке улова).
struct CatchShareCardButton: View {
    let catchID: UUID
    /// Публичный улов можно открыть в браузере — в сообщении ссылка на его страницу.
    var isPublic = false

    @Environment(SessionStore.self) private var session
    @Environment(SpeciesStore.self) private var speciesStore
    @State private var showsSheet = false

    private struct Loaded {
        let card: CatchShareCard
        let speciesName: String
        let photo: UIImage?
    }

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accent)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("share.title"))
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showsSheet) {
            ShareCardSheet(
                previewTitle: "Dalada",
                load: { await load() },
                message: { loaded in
                    let link = isPublic ? WebLink.catchPage(catchID) : ShareCardLink.site
                    return String(localized: "share.message.catch \(loaded.speciesName) \(link.absoluteString)")
                }
            ) { loaded, format in
                CatchShareCardView(card: loaded.card, speciesName: loaded.speciesName, photo: loaded.photo, format: format)
            }
        }
    }

    private func load() async -> Loaded? {
        guard let backend = session.backend,
              let card = try? await backend.catchShareCard(catchID)
        else { return nil }
        await speciesStore.loadIfNeeded()
        var photo: UIImage?
        if let path = card.photoPath,
           let url = try? await backend.signedMediaURLs(paths: [path])[path] {
            photo = await PhotoCache.shared.image(path: path, url: url)
        }
        return Loaded(card: card, speciesName: speciesStore.name(for: card.speciesID), photo: photo)
    }
}
