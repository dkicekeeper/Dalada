import DaladaCore
import DesignTokens
import Foundation
import SwiftUI

/// Текст обсуждения, где @username — ссылка на профиль (`dalada://u/<username>`).
enum MentionText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for part in Mentions.parts(in: text) {
            switch part {
            case .text(let plain):
                result.append(AttributedString(plain))
            case .mention(let written, let username):
                var mention = AttributedString(written)
                mention.link = InviteLink.url(username: username)
                mention.foregroundColor = AppColors.accent
                result.append(mention)
            }
        }
        return result
    }
}

/// Человек, упомянутый в обсуждении, — для перехода в профиль.
struct MentionedUser: Identifiable, Hashable {
    let username: String
    var id: String { username }
}
