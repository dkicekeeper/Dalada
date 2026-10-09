import Foundation
import Testing
@testable import DaladaCore

@Suite("Отчёты о сбоях")
struct DiagnosticsTests {
    private func report(_ signature: String) -> DiagnosticReport {
        DiagnosticReport(kind: .crash, appVersion: "1.0 (139)", osVersion: "iOS 26.0", deviceModel: "iPhone17,1",
                         signature: signature, payload: "{}")
    }

    @Test func encodesForRPC() throws {
        let data = try JSONEncoder().encode([report("crash sig=11")])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(json.first?["kind"] == "crash")
        #expect(json.first?["app_version"] == "1.0 (139)")
        #expect(json.first?["device_model"] == "iPhone17,1")
        #expect(json.first?.count == 6)
    }

    @Test func dropsLargeStackAndTrimsFields() {
        let big = DiagnosticReport(kind: .hang, appVersion: String(repeating: "9", count: 50), osVersion: "iOS",
                                   deviceModel: "iPhone", signature: "hang 3s",
                                   payload: String(repeating: "x", count: DiagnosticReport.maxPayloadBytes + 1))
        #expect(big.payload == "{}")
        #expect(big.appVersion.count == 32)
    }

    @Test func crashSignature() {
        #expect(Diagnostics.crashSignature(exceptionType: 1, exceptionCode: nil, signal: 11, terminationReason: nil)
            == "crash exc=1 sig=11")
        #expect(Diagnostics.crashSignature(exceptionType: nil, exceptionCode: nil, signal: nil, terminationReason: "  Namespace SPRINGBOARD ")
            == "crash Namespace SPRINGBOARD")
    }

    @Test func queueKeepsNewest() {
        let old = (1...15).map { report("old \($0)") }
        let new = (1...10).map { report("new \($0)") }
        let queue = Diagnostics.enqueue(new, to: old)
        #expect(queue.count == Diagnostics.queueLimit)
        #expect(queue.first?.signature == "old 6")
        #expect(queue.last?.signature == "new 10")
    }
}
