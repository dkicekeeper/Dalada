import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI

// MARK: - Строка статьи

/// Статья в списке: раздел, название, кратко, время чтения (`ItemRow` из DesignKit).
struct ArticleRow: View {
    let article: Article

    @Environment(ArticlesStore.self) private var store

    private var language: String { PackingFormat.language }

    /// Где начинается текст: после значка раздела и промежутка (метка ссылки не передаёт отступ).
    static let dividerInset = AppIconSize.lg + AppSpacing.xs + AppSpacing.md

    var body: some View {
        ItemRow(
            article.title.text(for: language),
            detail: article.summary.text(for: language),
            meta: [MetaLine(meta, tint: AppColors.textTertiary)],
            leading: .glyph(article.category.systemImage),
            // Статьи плотнее других строк (описание под названием): sm и xxs, как до DesignKit 8.1.0.
            verticalPadding: AppSpacing.sm
        )
        .padding(.vertical, AppSpacing.xxs)
    }

    private var meta: [MetaItem] {
        var items: [MetaItem] = [
            .text(Text(LocalizedStringKey(article.category.titleKey))),
            .text(Text("article.minutes \(article.readingMinutes(language: language))")),
        ]
        if store.isSaved(article) {
            items.append(.symbol("bookmark.fill", accessibilityLabel: String(localized: "article.saved")))
        }
        return items
    }
}

// MARK: - Все статьи

/// Что показывать в списке статей.
enum ArticleFilter: Hashable {
    case all
    case saved
    case category(ArticleCategory)
}

/// «Статьи и советы»: все, сохранённые, по разделам.
struct ArticlesListView: View {
    @Environment(ArticlesStore.self) private var store
    @State private var filter: ArticleFilter = .all

    private var shown: [Article] {
        switch filter {
        case .all: store.articles
        case .saved: store.saved
        case .category(let category): store.articles.filter { $0.category == category }
        }
    }

    // DesignKit 8.0.0: стеклянная секция на странице (до этого List).
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        chip(Text("articles.filter.all"), .all)
                        chip(Text("articles.filter.saved"), .saved)
                        ForEach(store.categories) { category in
                            chip(Text(LocalizedStringKey(category.titleKey)), .category(category))
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .contentMargins(.horizontal, AppSpacing.lg, for: .scrollContent)
                .padding(.horizontal, -AppSpacing.lg)

                if shown.isEmpty {
                    Text(filter == .saved ? LocalizedStringKey("articles.saved.empty") : LocalizedStringKey("articles.empty"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    CardList(shown, layout: .section) { article in
                        NavigationLink {
                            ArticleView(article: article)
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                ArticleRow(article: article)
                                DisclosureChevron()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .rowDividerInset(ArticleRow.dividerInset)
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("articles.title")
        .task { await store.loadIfNeeded() }
    }

    private func chip(_ title: Text, _ value: ArticleFilter) -> some View {
        Button {
            filter = value
        } label: {
            title
        }
        .buttonStyle(.plain)
        .filterChipStyle(isSelected: filter == value)
    }
}

// MARK: - Статья

/// Читалка статьи: раздел, время чтения, текст с заголовками, списками и выносками;
/// «Сохранить» и «Поделиться».
struct ArticleView: View {
    let article: Article

    @Environment(ArticlesStore.self) private var store

    private var language: String { PackingFormat.language }
    private var blocks: [ArticleBlock] { ArticleMarkdown.blocks(article.body.text(for: language)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label(LocalizedStringKey(article.category.titleKey), systemImage: article.category.systemImage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: article.title.text(for: language))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                Text("article.minutes \(article.readingMinutes(language: language))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                ArticleBody(blocks.map(\.designKitBlock))
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(Text("article.share"))
                }
                Button {
                    store.toggleSaved(article)
                } label: {
                    Image(systemName: store.isSaved(article) ? "bookmark.fill" : "bookmark")
                        .accessibilityLabel(store.isSaved(article) ? Text("article.unsave") : Text("article.save"))
                }
            }
        }
    }

    /// Название, кратко и подпись — для «Поделиться».
    private var shareText: String {
        article.title.text(for: language) + "\n\n" + article.summary.text(for: language)
            + "\n\n" + String(localized: "article.shareSignature")
    }
}

/// Блок статьи Dalada как блок `ArticleBody` из DesignKit (разбор Markdown — `ArticleMarkdown`).
extension ArticleBlock {
    var designKitBlock: ArticleBody.Block {
        switch self {
        case .heading(let text, let level): .heading(text, level: level)
        case .paragraph(let text): .paragraph(text)
        case .bullets(let items): .bullets(items)
        case .steps(let items): .steps(items)
        case .note(let text): .note(text)
        }
    }
}
