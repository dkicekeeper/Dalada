import Foundation

// MARK: - Пуш-уведомления

/// Окружение APNs: сборки из Xcode — `sandbox`, TestFlight и App Store — `production`.
public enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

public enum PushToken {
    /// Токен устройства строкой: шестнадцатеричные цифры в нижнем регистре.
    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// Ссылка на обсуждение (из пуша об ответе): `dalada://thread/<id>`.
public enum ThreadLink {
    static let host = "thread"

    public static func url(threadID: UUID) -> URL {
        URL(string: "\(InviteLink.scheme)://\(host)/\(threadID.uuidString.lowercased())")!
    }

    public static func threadID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}

/// Общие сборы (из пуша-приглашения): `dalada://packing/<id>`.
public enum PackingLink {
    static let host = "packing"

    public static func url(packingID: UUID) -> URL {
        URL(string: "\(InviteLink.scheme)://\(host)/\(packingID.uuidString.lowercased())")!
    }

    public static func packingID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == InviteLink.scheme, url.host?.lowercased() == host else { return nil }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}

/// Друг показывает, где он (из пуша): `dalada://live` — «Главная» с «Сейчас на выезде».
public enum LiveLink {
    static let host = "live"

    public static let url = URL(string: "\(InviteLink.scheme)://\(host)")!

    public static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == InviteLink.scheme && url.host?.lowercased() == host
    }
}
