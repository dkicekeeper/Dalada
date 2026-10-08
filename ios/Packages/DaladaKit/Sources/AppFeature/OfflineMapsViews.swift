import DaladaCore
import DesignComponents
import DesignTokens
import MapEngine
import SwiftUI

/// «Карты без сети»: районы, которые можно скачать заранее, — карта открывается там без связи.
struct OfflineMapsView: View {
    let environment: AppEnvironment

    @State private var maps = OfflineMaps.shared

    var body: some View {
        List {
            Section {
                ForEach(MapRegions.all) { region in
                    OfflineRegionRow(
                        region: region,
                        state: maps.state(of: region),
                        download: { maps.download(region, styleURL: environment.config.mapStyleURL) },
                        pause: { maps.pause(region) },
                        remove: { maps.remove(region) }
                    )
                }
            } footer: {
                Text("offlineMaps.footer")
            }

            if maps.totalBytes > 0 {
                Section {
                    LabeledContent("offlineMaps.total") {
                        Text(verbatim: OfflineMapsFormat.size(maps.totalBytes))
                    }
                }
            }
        }
        .navigationTitle("offlineMaps.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Район: название, размер или ход скачивания, кнопка действия; смахнуть — удалить.
/// `DownloadRow` из DesignKit над состоянием `OfflineMaps`.
struct OfflineRegionRow: View {
    let region: MapRegion
    let state: OfflineMaps.State
    let download: () -> Void
    let pause: () -> Void
    let remove: () -> Void

    var body: some View {
        DownloadRow(
            String(localized: String.LocalizationValue(region.titleKey)),
            status: status,
            caption: caption,
            onDownload: download,
            onPause: pause,
            downloadLabel: String(localized: "offlineMaps.download"),
            pauseLabel: String(localized: "offlineMaps.pause")
        )
        .swipeActions {
            if hasData {
                Button("offlineMaps.delete", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }

    private var hasData: Bool {
        switch state {
        case .notDownloaded: false
        default: true
        }
    }

    private var status: DownloadRow.Status {
        switch state {
        case .notDownloaded: .available
        case .downloading(let progress, _): .downloading(progress)
        case .paused: .paused
        case .downloaded: .downloaded
        case .failed: .failed
        }
    }

    private var caption: String {
        switch state {
        case .notDownloaded:
            String(localized: "offlineMaps.estimate \(OfflineMapsFormat.size(region.estimatedBytes))")
        case .downloading(let progress, let bytes):
            String(localized: "offlineMaps.progress \(Int(progress * 100)) \(OfflineMapsFormat.size(bytes))")
        case .paused(let progress, _):
            String(localized: "offlineMaps.paused \(Int(progress * 100))")
        case .downloaded(let bytes):
            String(localized: "offlineMaps.downloaded \(OfflineMapsFormat.size(bytes))")
        case .failed(let message):
            message.isEmpty ? String(localized: "offlineMaps.failed") : message
        }
    }
}

enum OfflineMapsFormat {
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// «2 района · 80 МБ» для строки в «Лайфхаках».
    @MainActor
    static func summary(_ maps: OfflineMaps) -> String {
        let downloaded = MapRegions.all.filter {
            if case .downloaded = maps.state(of: $0) { true } else { false }
        }.count
        guard downloaded > 0 else { return String(localized: "offlineMaps.summary.none") }
        return String(localized: "offlineMaps.summary \(downloaded) \(size(maps.totalBytes))")
    }
}
