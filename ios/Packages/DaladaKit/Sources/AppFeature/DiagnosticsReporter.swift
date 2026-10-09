import Backend
import DaladaCore
import Foundation
import MetricKit

/// Отчёты iOS о сбоях и зависаниях (MetricKit). iOS присылает их раз в день и только если человек
/// разрешил в Настройках делиться аналитикой с разработчиками. Отчёты копятся в файле на телефоне
/// (не больше 20) и уходят на сервер, когда человек вошёл и есть сеть.
@MainActor
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    private var isSending = false

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics.json")
    }

    /// При запуске: подписаться на отчёты (в том числе пришедшие, пока приложение не работало).
    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap(Self.reports(from:))
        guard !reports.isEmpty else { return }
        Task { @MainActor in self.save(Diagnostics.enqueue(reports, to: self.load())) }
    }

    /// Отправить накопленное; при ошибке отчёты остаются до следующего раза.
    func flush(backend: BackendClient?, isSignedIn: Bool) async {
        guard isSignedIn, let backend, !isSending else { return }
        let pending = load()
        guard !pending.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await backend.reportDiagnostics(pending)
            save([])
        } catch {
            // Сеть или сервер — попробуем при следующем возврате в приложение.
        }
    }

    private func load() -> [DiagnosticReport] {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticReport].self, from: data)) ?? []
    }

    private func save(_ reports: [DiagnosticReport]) {
        guard let url = Self.fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if reports.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(reports) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Из MetricKit в отчёты

    private nonisolated static func reports(from payload: MXDiagnosticPayload) -> [DiagnosticReport] {
        var result: [DiagnosticReport] = []
        for crash in payload.crashDiagnostics ?? [] {
            let signature = Diagnostics.crashSignature(
                exceptionType: crash.exceptionType?.intValue,
                exceptionCode: crash.exceptionCode?.intValue,
                signal: crash.signal?.intValue,
                terminationReason: crash.terminationReason
            )
            result.append(report(.crash, crash, signature: signature, stack: crash.callStackTree))
        }
        for hang in payload.hangDiagnostics ?? [] {
            let seconds = Int(hang.hangDuration.converted(to: .seconds).value.rounded())
            result.append(report(.hang, hang, signature: "hang \(seconds)s", stack: hang.callStackTree))
        }
        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            let seconds = Int(cpu.totalCPUTime.converted(to: .seconds).value.rounded())
            result.append(report(.cpu, cpu, signature: "cpu \(seconds)s", stack: cpu.callStackTree))
        }
        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            let megabytes = Int(disk.totalWritesCaused.converted(to: .megabytes).value.rounded())
            result.append(report(.disk, disk, signature: "disk \(megabytes)MB", stack: disk.callStackTree))
        }
        for launch in payload.appLaunchDiagnostics ?? [] {
            let seconds = launch.launchDuration.converted(to: .seconds).value
            result.append(report(.launch, launch, signature: String(format: "launch %.1fs", seconds), stack: launch.callStackTree))
        }
        return result
    }

    private nonisolated static func report(_ kind: DiagnosticReport.Kind, _ diagnostic: MXDiagnostic, signature: String,
                                           stack: MXCallStackTree) -> DiagnosticReport {
        let meta = diagnostic.metaData
        return DiagnosticReport(
            kind: kind,
            appVersion: "\(diagnostic.applicationVersion) (\(meta.applicationBuildVersion))",
            osVersion: meta.osVersion,
            deviceModel: meta.deviceType,
            signature: signature,
            payload: String(data: stack.jsonRepresentation(), encoding: .utf8) ?? "{}"
        )
    }
}
