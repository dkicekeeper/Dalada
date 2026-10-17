import Foundation
import Network

/// Появление сети — сигнал отправить офлайн-очередь.
enum NetworkMonitor {
    /// Событие на каждый переход «нет сети → есть сеть».
    static func becameAvailable() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            let last = LastStatus()
            monitor.pathUpdateHandler = { path in
                // Вызывается последовательно на очереди монитора.
                let satisfied = path.status == .satisfied
                if satisfied, last.satisfied == false {
                    continuation.yield()
                }
                last.satisfied = satisfied
            }
            let holder = MonitorHolder(monitor: monitor)
            continuation.onTermination = { _ in holder.monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.dalada.network"))
        }
    }

    /// Состояние сети на каждое изменение; первое — сразу после подписки.
    static func statuses() -> AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(NetworkStatus(isAvailable: path.status == .satisfied, isExpensive: path.isExpensive))
            }
            let holder = MonitorHolder(monitor: monitor)
            continuation.onTermination = { _ in holder.monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.dalada.network.status"))
        }
    }

    /// Последнее состояние сети; меняется только на очереди монитора.
    private final class LastStatus: @unchecked Sendable {
        var satisfied: Bool?
    }

    private final class MonitorHolder: @unchecked Sendable {
        let monitor: NWPathMonitor
        init(monitor: NWPathMonitor) { self.monitor = monitor }
    }
}

/// Есть ли связь и платная ли она (мобильная сеть, точка доступа на телефоне).
struct NetworkStatus: Equatable, Sendable {
    var isAvailable: Bool
    var isExpensive: Bool
}
