import Backend
import DaladaCore
import DesignComponents
import DesignTokens
import Foundation
import SwiftUI

// MARK: - Лист экспорта

/// Лист экспорта: готовит файл (с ходом работы) и даёт «Поделиться» — сохранить в «Файлы», отправить
/// по AirDrop или в мессенджер.
struct ExportSheet: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey
    let prepare: @MainActor (_ progress: @escaping @MainActor (String) -> Void) async throws -> URL

    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var progress: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: 0)
                if let fileURL {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: AppIconSize.xxl))
                        .foregroundStyle(AppColors.success)
                    Text(verbatim: fileURL.lastPathComponent)
                        .font(AppTypography.bodyEmphasis)
                        .multilineTextAlignment(.center)
                    ShareLink(item: fileURL) {
                        Label("export.share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                } else if let errorText {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: String(localized: "export.failed"),
                        description: errorText,
                        actionTitle: String(localized: "common.retry"),
                        action: { Task { await run() } },
                        style: .error
                    )
                } else {
                    ProgressView()
                    Text(verbatim: progress ?? String(localized: "export.preparing"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                Text(footer)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await run() }
        }
        .presentationDetents([.medium, .large])
    }

    private func run() async {
        errorText = nil
        fileURL = nil
        do {
            fileURL = try await prepare { progress = $0 }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Файлы

enum ExportFiles {
    /// Своя поездка в GPX: точки со временем и высотой, целиком (начало и конец не обрезаны).
    @MainActor
    static func tripGPX(_ trip: TripSummary, backend: BackendClient) async throws -> URL {
        let points = try await backend.myTripPoints(trip.id)
        let directory = try freshDirectory()
        let url = directory.appendingPathComponent(ExportFileName.gpx(title: trip.title, date: trip.startedAt))
        try GPX.document(name: trip.title, points: points).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Архив «Dalada 2026-10-06.zip»: `data.json` (всё своё), `trips/*.gpx`, `photos/*.jpg`.
    @MainActor
    static func archive(
        backend: BackendClient,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let directory = try freshDirectory()
        let folder = directory.appendingPathComponent(ExportFileName.archive(date: .now), isDirectory: true)
        let tripsFolder = folder.appendingPathComponent("trips", isDirectory: true)
        let photosFolder = folder.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: tripsFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: photosFolder, withIntermediateDirectories: true)

        progress(String(localized: "export.progress.data"))
        let data = try await backend.exportMyData()
        try data.write(to: folder.appendingPathComponent("data.json"))

        let outline = try ExportOutline.decode(data)
        let names = outline.gpxFileNames()
        for trip in outline.trips {
            guard let name = names[trip.id] else { continue }
            try GPX.document(name: trip.title ?? "Dalada", points: trip.track)
                .write(to: tripsFolder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        // Фото — по одному; не скачалось — без него, остальное в архиве.
        for (index, photo) in outline.photos.enumerated() {
            progress(String(localized: "export.progress.photos \(index + 1) \(outline.photos.count)"))
            guard let jpeg = try? await backend.downloadMedia(path: photo.storagePath) else { continue }
            try jpeg.write(to: photosFolder.appendingPathComponent(photo.id.uuidString.lowercased() + ".jpg"))
        }

        progress(String(localized: "export.progress.zip"))
        return try zip(folder, into: directory)
    }

    /// Упаковать папку в .zip средствами системы (`NSFileCoordinator`, `.forUploading`).
    static func zip(_ folder: URL, into directory: URL) throws -> URL {
        let target = directory.appendingPathComponent(folder.lastPathComponent + ".zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: zipURL, to: target)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        try? FileManager.default.removeItem(at: folder)
        return target
    }

    /// Своя временная папка: старые выгрузки удаляем, чтобы не копились.
    private static func freshDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
