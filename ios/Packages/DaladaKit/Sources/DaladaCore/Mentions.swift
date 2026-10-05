import Foundation

/// Упоминания @username в обсуждениях — те же правила, что у базы (`private.mentioned_users`):
/// `@` в начале или после пробела и знаков (не внутри почты или слова), дальше 3–30 символов
/// username; точка в конце — конец предложения, не часть имени.
public enum Mentions {
    public enum Part: Equatable, Sendable {
        case text(String)
        /// Как написано в тексте (`@Bob`) и username для ссылки (`bob`).
        case mention(String, username: String)
    }

    private static let usernameCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")

    /// Текст по частям: обычный текст и упоминания подряд.
    public static func parts(in text: String) -> [Part] {
        var parts: [Part] = []
        var plain = ""
        var index = text.startIndex
        var previous: Character?
        while index < text.endIndex {
            let character = text[index]
            if character == "@", !isWordCharacter(previous) {
                var end = text.index(after: index)
                while end < text.endIndex, usernameCharacters.contains(text[end]),
                      text.distance(from: index, to: end) <= 30 {
                    end = text.index(after: end)
                }
                var name = String(text[text.index(after: index)..<end])
                while name.hasSuffix(".") {
                    name.removeLast()
                    end = text.index(before: end)
                }
                if UsernameRules.isValidFormat(name) {
                    if !plain.isEmpty {
                        parts.append(.text(plain))
                        plain = ""
                    }
                    parts.append(.mention(String(text[index..<end]), username: name.lowercased()))
                    previous = text[text.index(before: end)]
                    index = end
                    continue
                }
            }
            plain.append(character)
            previous = character
            index = text.index(after: index)
        }
        if !plain.isEmpty {
            parts.append(.text(plain))
        }
        return parts
    }

    /// Буква любого алфавита, цифра, `_`, `.` или `@` перед `@` — это не упоминание (почта, слово).
    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "." || character == "@"
    }
}
