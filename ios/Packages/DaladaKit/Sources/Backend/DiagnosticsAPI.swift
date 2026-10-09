import DaladaCore
import Foundation
import Supabase

// MARK: - Отчёты о сбоях

extension BackendClient {
    /// Отправляет отчёты MetricKit (RPC `report_diagnostics`); возвращает, сколько сервер сохранил.
    /// Кто прислал, сервер не хранит — только счётчик отчётов за день.
    @discardableResult
    public func reportDiagnostics(_ reports: [DiagnosticReport]) async throws -> Int {
        struct Params: Encodable, Sendable { let p_items: [DiagnosticReport] }
        return try await supabase.rpc("report_diagnostics", params: Params(p_items: reports)).execute().value
    }
}
