import Foundation

// MARK: - Отчёты о сбоях (MetricKit)

/// Отчёт iOS о сбое или зависании для RPC `report_diagnostics`. Без данных человека: версия
/// приложения и iOS, модель телефона, короткая подпись и стек вызовов от MetricKit.
public struct DiagnosticReport: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case crash, hang, cpu, disk, launch
    }

    /// Стек длиннее — не отправляем (на сервере предел 64 КБ), остаётся подпись.
    public static let maxPayloadBytes = 60_000

    public let kind: Kind
    public let appVersion: String
    public let osVersion: String
    public let deviceModel: String
    public let signature: String
    /// JSON стека вызовов от MetricKit или `{}`.
    public let payload: String

    public init(kind: Kind, appVersion: String, osVersion: String, deviceModel: String, signature: String, payload: String) {
        self.kind = kind
        self.appVersion = String(appVersion.prefix(32))
        self.osVersion = String(osVersion.prefix(64))
        self.deviceModel = String(deviceModel.prefix(64))
        self.signature = String(signature.prefix(300))
        self.payload = payload.utf8.count <= Self.maxPayloadBytes ? payload : "{}"
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case appVersion = "app_version"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case signature
        case payload
    }
}

public enum Diagnostics {
    /// Сколько отчётов держим на телефоне до отправки (сервер принимает 20 в день).
    public static let queueLimit = 20

    /// Подпись сбоя: вид, тип исключения, сигнал и причина завершения — по ней группируем отчёты.
    public static func crashSignature(exceptionType: Int?, exceptionCode: Int?, signal: Int?, terminationReason: String?) -> String {
        var parts = ["crash"]
        if let exceptionType { parts.append("exc=\(exceptionType)") }
        if let exceptionCode { parts.append("code=\(exceptionCode)") }
        if let signal { parts.append("sig=\(signal)") }
        if let reason = terminationReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            parts.append(String(reason.prefix(120)))
        }
        return parts.joined(separator: " ")
    }

    /// Очередь на телефоне: новые в конце, при переполнении теряются самые старые.
    public static func enqueue(_ new: [DiagnosticReport], to queue: [DiagnosticReport]) -> [DiagnosticReport] {
        Array((queue + new).suffix(queueLimit))
    }
}
