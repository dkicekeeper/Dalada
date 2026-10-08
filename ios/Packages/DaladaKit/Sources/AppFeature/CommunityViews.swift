import Backend
import DaladaCore
import DaladaUI
import DesignComponents
import DesignTokens
import PhotosUI
import SwiftUI
import Sync

// MARK: - Звёзды

// MARK: - Отзывы

/// Отзывы публичного места в карточке: средняя оценка и распределение, свой отзыв, три самых
/// полезных и «Все отзывы».
struct PlaceReviewsSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment
    /// Во вкладке карточки места заголовок — сам чип.
    var showsHeader = true

    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(ReactionStore.self) private var reactions
    @State private var summary: ReviewSummary?
    @State private var reviews: [PlaceReview] = []
    @State private var showsForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsHeader {
                SectionHeader(String(localized: "reviews.title"), systemImage: "star.bubble")
            }
            if let summary {
                if summary.reviewsCount > 0 {
                    ReviewSummaryView(summary: summary)
                    reviewAction(summary)
                } else {
                    // Пусто — сразу и что делать: «Оставить отзыв», если уже можно.
                    let canWrite = session.profile != nil && summary.myReview == nil && summary.canReview
                    EmptyState(
                        icon: "star.bubble",
                        title: String(localized: "reviews.empty.title"),
                        description: String(localized: "reviews.empty"),
                        actionTitle: canWrite ? String(localized: "reviews.write") : nil,
                        action: { showsForm = true }
                    )
                    if !canWrite {
                        reviewAction(summary)
                    }
                }
            }
            ForEach(reviews) { review in
                ReviewRow(review: review, environment: environment) { blocked in
                    reviews.removeAll { $0.author.id == blocked }
                }
            }
            if let summary, summary.reviewsCount > reviews.count {
                NavigationLink {
                    ReviewsListView(placeID: place.id, placeName: place.name, environment: environment)
                } label: {
                    Text("reviews.all \(summary.reviewsCount)")
                        .font(AppTypography.bodySmall)
                }
            }
        }
        .task(id: place.id) { await load() }
        // Чекин из очереди дошёл до сервера — теперь можно оставить отзыв.
        .onChange(of: sync.sentCount) { _, _ in
            Task { await load() }
        }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await load() } }) {
            ReviewFormView(placeID: place.id, placeName: place.name, existing: summary?.myReview, environment: environment)
        }
    }

    @ViewBuilder
    private func reviewAction(_ summary: ReviewSummary) -> some View {
        if session.profile != nil {
            if summary.myReview != nil {
                Button {
                    showsForm = true
                } label: {
                    Label("reviews.edit", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .dsButton(.secondary)
            } else if summary.canReview {
                Button {
                    showsForm = true
                } label: {
                    Label("reviews.write", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .dsButton()
            } else {
                Label("reviews.checkinFirst", systemImage: "mappin.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func load() async {
        guard let backend = environment.backend else { return }
        summary = try? await backend.reviewSummary(place.id)
        reviews = (try? await backend.placeReviews(place.id, sort: .helpful, limit: 3)) ?? []
        for review in reviews {
            reactions.seed(ReactionKey(.review, review.id), review.helpful)
        }
        await reactions.loadCommentCounts(reviews.map { ReactionKey(.review, $0.id) })
    }
}

/// Средняя оценка, число отзывов и полоски по звёздам.
struct ReviewSummaryView: View {
    let summary: ReviewSummary

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.xxs) {
                Text(verbatim: (summary.ratingAverage ?? 0).formatted(.number.precision(.fractionLength(1))))
                    .font(AppTypography.h2)
                    .monospacedDigit()
                Rating(rating: summary.ratingAverage ?? 0, size: 12)
                Text("reviews.count \(summary.reviewsCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            VStack(spacing: AppSpacing.xxs) {
                ForEach((1...5).reversed(), id: \.self) { star in
                    HStack(spacing: AppSpacing.xs) {
                        Text(verbatim: "\(star)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 12)
                        LinearProgressBar(value: summary.share(of: star), color: AppColors.warning, height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("reviews.bar.accessibility \(star) \(summary.stars[star - 1])"))
                }
            }
        }
        .cardContentPadding()
        .cardStyle()
    }
}

/// Отзыв: автор, звёзды, когда был, текст, «Полезно».
struct ReviewRow: View {
    let review: PlaceReview
    /// Для ссылок на фото отзыва.
    var environment: AppEnvironment?
    /// Автора заблокировали — убрать его отзывы с экрана.
    var onBlocked: (@MainActor (UUID) -> Void)?

    @State private var photoURLs: [String: URL] = [:]

    var body: some View {
        ReviewCard(
            author: review.isOwn ? String(localized: "report.you") : review.author.label,
            rating: Double(review.rating),
            date: review.createdAt,
            subtitle: review.visitedOn.map {
                String(localized: "reviews.visited \($0.date().formatted(.dateTime.day().month(.wide).year()))")
            },
            text: review.body
        ) {
            if !review.isOwn {
                ModerationMenu(target: .review, targetID: review.id, author: review.author) {
                    onBlocked?(review.author.id)
                }
            }
        } media: {
            if !review.media.isEmpty {
                ReportPhotoStrip(media: review.media, urls: photoURLs)
                    .task(id: review.media.map(\.id)) { await loadPhotoURLs() }
            }
        } actions: {
            ReactionButton(key: ReactionKey(.review, review.id), isOwn: review.isOwn, style: .helpful)
            CommentsButton(key: ReactionKey(.review, review.id))
            if review.editedAt != nil {
                Text("reviews.edited")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private func loadPhotoURLs() async {
        guard let backend = environment?.backend else { return }
        let paths = review.media.flatMap { [$0.thumbnailPath, $0.path] }
        photoURLs = (try? await backend.signedMediaURLs(paths: paths)) ?? [:]
    }
}

/// Все отзывы места с сортировкой: новые, полезные, высокие, низкие.
struct ReviewsListView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    private static let pageSize = 30

    @Environment(ReactionStore.self) private var reactions
    @State private var sort: ReviewSort = .new
    @State private var reviews: [PlaceReview] = []
    @State private var hasMore = true

    var body: some View {
        List {
            Section {
                SegmentedPicker(
                    title: String(localized: "reviews.sort"),
                    selection: $sort,
                    options: ReviewSort.allCases.map {
                        (label: String(localized: String.LocalizationValue($0.titleKey)), value: $0)
                    }
                )
            }
            ForEach(reviews) { review in
                ReviewRow(review: review, environment: environment) { blocked in
                    reviews.removeAll { $0.author.id == blocked }
                }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if review.id == reviews.last?.id { Task { await loadMore() } }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(verbatim: placeName))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sort) { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let backend = environment.backend,
              let page = try? await backend.placeReviews(placeID, sort: sort, limit: Self.pageSize)
        else { return }
        reviews = page
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend,
              let page = try? await backend.placeReviews(placeID, sort: sort, limit: Self.pageSize, offset: reviews.count)
        else { return }
        let known = Set(reviews.map(\.id))
        reviews += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func seed(_ page: [PlaceReview]) {
        for review in page {
            reactions.seed(ReactionKey(.review, review.id), review.helpful)
        }
        Task { await reactions.loadCommentCounts(page.map { ReactionKey(.review, $0.id) }) }
    }
}

/// Отзыв: оценка, текст, когда были. Свой — можно изменить или удалить.
struct ReviewFormView: View {
    let placeID: UUID
    let placeName: String
    let existing: MyReview?
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var text = ""
    @State private var visitedDate = Date()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var confirmsDelete = false
    @State private var isPrepared = false
    /// Новые фото к отзыву (уже загруженные остаются).
    @State private var photos: [PhotoDraft] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoFailed = false

    var body: some View {
        EditSheetContainer(
            title: placeName,
            isSaveDisabled: !draft.isValid || isProcessingPhotos,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(header: String(localized: "reviews.form.rating")) {
                        RatingPicker(rating: $rating)
                            .padding(.vertical, AppSpacing.md)
                    }

                    FormSection(
                        header: String(localized: "reviews.form.text"),
                        footer: text.count > ReviewDraft.bodyLimit - 200 ? "\(text.count) / \(ReviewDraft.bodyLimit)" : nil
                    ) {
                        FormTextField(
                            text: $text,
                            placeholder: String(localized: "reviews.form.placeholder"),
                            style: .rowMultiline(min: 3, max: 10)
                        )
                    }

                    FormSection {
                        DatePickerRow(
                            title: String(localized: "reviews.form.visitedOn"),
                            selection: $visitedDate,
                            maxDate: Date()
                        )
                    }

                    FormSection(
                        header: String(localized: "reviews.form.photos"),
                        footer: photoFailed ? nil : String(localized: "reviews.form.photosFooter")
                    ) {
                        if !photos.isEmpty {
                            PhotoDraftStrip(photos: photos) { id in
                                photos.removeAll { $0.id == id }
                            }
                            .contentMargins(.horizontal, AppSpacing.lg, for: .scrollContent)
                            .padding(.vertical, AppSpacing.md)
                        }
                        if isProcessingPhotos {
                            // Фото сжимаются: плитка-скелетон на месте будущего фото.
                            PhotoTileSkeleton()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)
                        } else if photos.count < ReviewDraft.photoLimit {
                            PhotosPicker(
                                selection: $pickerItems,
                                maxSelectionCount: ReviewDraft.photoLimit - photos.count,
                                matching: .images
                            ) {
                                PickerRowLabel(String(localized: "reviews.form.addPhotos"), systemImage: "photo.on.rectangle.angled")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if photoFailed {
                        InlineStatusText(message: String(localized: "photo.failed"), type: .error)
                    }

                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }

                    if existing != nil {
                        FormSection {
                            ActionSettingsRow(
                                title: String(localized: "reviews.delete"),
                                isDestructive: true,
                                config: .standard
                            ) {
                                confirmsDelete = true
                            }
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
        .confirmationDialog("reviews.deleteConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("reviews.delete", role: .destructive) {
                Task { await delete() }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .onAppear {
            guard !isPrepared else { return }
            isPrepared = true
            let initial = ReviewDraft(placeID: placeID, existing: existing)
            rating = initial.rating
            text = initial.body
            visitedDate = initial.visitedOn.date()
        }
    }

    private var draft: ReviewDraft {
        var draft = ReviewDraft(placeID: placeID, existing: existing)
        draft.rating = rating
        draft.body = text
        draft.visitedOn = CalendarDay(visitedDate)
        return draft
    }

    private func save() async {
        guard let backend = environment.backend, draft.isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let reviewID = try await backend.saveReview(draft)
            // Не загрузились фото — отзыв уже сохранён; «Сохранить» ещё раз догрузит их.
            try await backend.addReviewPhotos(photos, reviewID: reviewID)
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
        }
    }

    /// Сжимает выбранные фото по одному (не больше лимита).
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        pickerItems = []
        isProcessingPhotos = true
        photoFailed = false
        defer { isProcessingPhotos = false }
        for item in items {
            guard photos.count < ReviewDraft.photoLimit else { break }
            if let photo = await PhotoCompressor.draft(from: item) {
                photos.append(photo)
            } else {
                photoFailed = true
            }
        }
    }

    private func delete() async {
        guard let backend = environment.backend, let existing else { return }
        do {
            try await backend.deleteReview(existing.id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Понятный текст ошибки для отзывов и обсуждений.
enum CommunityMessage {
    static func text(for error: any Error) -> String {
        if let refusal = CommunityRefusal(error) {
            return String(localized: String.LocalizationValue(refusal.messageKey))
        }
        return error.localizedDescription
    }
}

// MARK: - Обсуждения

/// Обсуждения публичного места в карточке: три свежих по активности, «Все», «Новое обсуждение».
struct PlaceThreadsSection: View {
    let place: PlaceDetails
    let environment: AppEnvironment
    /// Во вкладке карточки места заголовок — сам чип.
    var showsHeader = true

    @Environment(SessionStore.self) private var session
    @State private var threads: [ThreadSummary] = []
    @State private var isLoaded = false
    @State private var showsForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsHeader {
                SectionHeader(String(localized: "threads.title"), systemImage: "bubble.left.and.bubble.right") {
                    if threads.count > 3 { allThreadsLink }
                }
            } else {
                // В карточке места заголовок даёт вкладка: ссылка «Все» одна у правого края.
                HStack {
                    Spacer(minLength: 0)
                    if threads.count > 3 {
                        allThreadsLink.font(AppTypography.bodySmall)
                    }
                }
            }
            if threads.isEmpty && isLoaded {
                // Пусто — сразу и что делать: «Новое обсуждение» после входа.
                EmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: String(localized: "threads.empty.title"),
                    description: String(localized: "threads.empty"),
                    actionTitle: session.profile != nil ? String(localized: "threads.new") : nil,
                    action: { showsForm = true }
                )
            }
            ForEach(threads.prefix(3)) { thread in
                NavigationLink {
                    ThreadView(threadID: thread.id, environment: environment)
                } label: {
                    ThreadRow(thread: thread)
                }
                .buttonStyle(.plain)
            }
            if session.profile != nil && !threads.isEmpty {
                Button {
                    showsForm = true
                } label: {
                    Label("threads.new", systemImage: "plus.bubble")
                        .frame(maxWidth: .infinity)
                }
                .dsButton(.secondary)
            }
        }
        .task(id: place.id) { await load() }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await load() } }) {
            ThreadFormView(placeID: place.id, placeName: place.name, environment: environment)
        }
    }

    private var allThreadsLink: some View {
        NavigationLink {
            ThreadsListView(placeID: place.id, placeName: place.name, environment: environment)
        } label: {
            Text("threads.all")
        }
    }

    private func load() async {
        defer { isLoaded = true }
        guard let backend = environment.backend else { return }
        threads = (try? await backend.placeThreads(place.id, limit: 4)) ?? []
    }
}

/// Строка обсуждения: заголовок, начало текста, ответы и последняя активность.
struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        ThreadCard(
            title: thread.title,
            preview: thread.bodyPreview,
            repliesCount: thread.postsCount,
            author: thread.author.label,
            lastActivity: thread.lastActivityAt
        )
    }
}

/// Все обсуждения места.
struct ThreadsListView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    private static let pageSize = 30

    @Environment(SessionStore.self) private var session
    @State private var threads: [ThreadSummary] = []
    @State private var hasMore = true
    @State private var showsForm = false

    var body: some View {
        List {
            ForEach(threads) { thread in
                NavigationLink {
                    ThreadView(threadID: thread.id, environment: environment)
                } label: {
                    ThreadRow(thread: thread)
                }
                .listRowSeparator(.hidden)
                .onAppear {
                    if thread.id == threads.last?.id { Task { await loadMore() } }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("threads.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.profile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("threads.new", systemImage: "plus") {
                        showsForm = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsForm, onDismiss: { Task { await reload() } }) {
            ThreadFormView(placeID: placeID, placeName: placeName, environment: environment)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let backend = environment.backend,
              let page = try? await backend.placeThreads(placeID, limit: Self.pageSize)
        else { return }
        threads = page
        hasMore = page.count >= Self.pageSize
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend,
              let page = try? await backend.placeThreads(placeID, limit: Self.pageSize, offset: threads.count)
        else { return }
        let known = Set(threads.map(\.id))
        threads += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
    }
}

/// Новое обсуждение: заголовок и текст.
struct ThreadFormView: View {
    let placeID: UUID
    let placeName: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var threadID = UUID()
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        EditSheetContainer(
            title: placeName,
            saveTitle: String(localized: "threads.form.publish"),
            isSaveDisabled: !draft.isValid,
            isSaving: isSaving,
            wrapInForm: false,
            onSave: { Task { await save() } },
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    FormSection(
                        header: String(localized: "threads.form.title"),
                        footer: String(localized: "threads.form.hint")
                    ) {
                        FormTextField(
                            text: $title,
                            placeholder: String(localized: "threads.form.titlePlaceholder"),
                            style: .row
                        )
                    }
                    FormSection(header: String(localized: "threads.form.text")) {
                        FormTextField(
                            text: $text,
                            placeholder: String(localized: "threads.form.textPlaceholder"),
                            style: .rowMultiline(min: 4, max: 12)
                        )
                    }
                    if let saveError {
                        InlineStatusText(message: saveError, type: .error)
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    private var draft: ThreadDraft {
        var draft = ThreadDraft(placeID: placeID, id: threadID)
        draft.title = title
        draft.body = text
        return draft
    }

    private func save() async {
        guard let backend = environment.backend, draft.isValid else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.createThread(draft)
            // Ответы на обсуждение приходят пушем — объясним и спросим разрешение.
            Task { await NotificationPrimer.shared.offer() }
            dismiss()
        } catch {
            saveError = CommunityMessage.text(for: error)
        }
    }
}

/// Обсуждение: вопрос, ответы по порядку, поле ответа (с цитатой). Своё — можно удалить.
struct ThreadView: View {
    let threadID: UUID
    let environment: AppEnvironment

    private static let pageSize = 50

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(ReactionStore.self) private var reactions
    @State private var thread: ThreadDetails?
    @State private var posts: [ThreadPost] = []
    @State private var hasMore = true
    @State private var loadError: String?
    @State private var isNotFound = false
    @State private var replyText = ""
    @State private var replyQuote: PostQuote?
    @State private var replyID = UUID()
    @State private var isSending = false
    @State private var sendError: String?
    @State private var confirmsDeleteThread = false
    /// Подписка на ответы: `nil` — гость или ещё не загружена.
    @State private var isSubscribed: Bool?
    /// Профиль по нажатию на @username.
    @State private var mentioned: MentionedUser?
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else if isNotFound {
                EmptyState(
                    icon: "bubble.left.and.exclamationmark.bubble.right",
                    title: String(localized: "threads.notFound"),
                    description: String(localized: "threads.notFound.description")
                )
            } else if let loadError {
                EmptyState(
                    icon: "wifi.slash",
                    title: String(localized: "threads.failed"),
                    description: loadError,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await load() } },
                    style: .error
                )
            } else {
                VStack(spacing: AppSpacing.lg) {
                    ForEach(0..<4, id: \.self) { _ in CommentRowSkeleton() }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.lg)
                .frame(maxHeight: .infinity, alignment: .top)
                .skeletonLoadingLabel()
            }
        }
        .navigationTitle(Text(verbatim: thread?.placeName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if thread != nil, let isSubscribed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await setSubscribed(!isSubscribed) }
                    } label: {
                        Image(systemName: isSubscribed ? "bell.fill" : "bell")
                    }
                    .accessibilityLabel(Text(isSubscribed ? "threads.unsubscribe" : "threads.subscribe"))
                    .sensoryFeedback(.selection, trigger: isSubscribed)
                }
            }
            if let thread {
                ToolbarItem(placement: .topBarTrailing) {
                    if thread.isOwn {
                        Menu {
                            Button("threads.delete", systemImage: "trash", role: .destructive) {
                                confirmsDeleteThread = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text("profile.menu"))
                        }
                    } else {
                        // Автора обсуждения заблокировали — обсуждение больше не видно.
                        ModerationMenu(target: .thread, targetID: thread.id, author: thread.author, isToolbar: true) {
                            dismiss()
                        }
                    }
                }
            }
        }
        // @username в тексте — профиль здесь же, в обсуждении.
        .environment(\.openURL, OpenURLAction { url in
            guard let username = InviteLink.username(from: url) else { return .systemAction }
            mentioned = MentionedUser(username: username)
            return .handled
        })
        .navigationDestination(item: $mentioned) { user in
            UserProfileView(username: user.username, environment: environment)
        }
        .confirmationDialog("threads.deleteConfirm", isPresented: $confirmsDeleteThread, titleVisibility: .visible) {
            Button("threads.delete", role: .destructive) {
                Task { await deleteThread() }
            }
        }
        .task { await load() }
    }

    private func content(_ thread: ThreadDetails) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(verbatim: thread.title)
                        .font(AppTypography.h3)
                    HStack(spacing: AppSpacing.sm) {
                        Text(verbatim: thread.isOwn ? String(localized: "report.you") : thread.author.label)
                        Text(verbatim: thread.createdAt.formatted(.relative(presentation: .named)))
                        if thread.editedAt != nil {
                            Text("reviews.edited")
                        }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    Text(MentionText.attributed(thread.body))
                        .font(AppTypography.body)
                        .textSelection(.enabled)
                }

                if posts.isEmpty {
                    Text("threads.noReplies")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }

                ForEach(posts) { post in
                    PostRow(
                        post: post,
                        canReply: session.profile != nil,
                        onReply: { quote(post) },
                        onDelete: { Task { await deletePost(post) } },
                        onBlocked: { Task { await load() } }
                    )
                    .onAppear {
                        if post.id == posts.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .refreshable { await load() }
        .safeAreaBar(edge: .bottom) {
            if session.profile != nil {
                composer
            }
        }
    }

    /// Поле ответа из DesignKit: стекло над обсуждением, цитата того, на что отвечают, кнопка
    /// отправки внутри.
    private var composer: some View {
        MessageComposer(
            text: $replyText,
            placeholder: String(localized: "threads.replyPlaceholder"),
            quote: replyQuote.map {
                MessageQuote(title: String(localized: "threads.replyingTo \(quoteAuthor($0))"), text: $0.body)
            },
            isSending: isSending,
            canSend: replyDraft.isValid,
            errorMessage: sendError,
            focus: $isReplyFocused,
            onCancelQuote: { replyQuote = nil }
        ) {
            Task { await send() }
        }
        .screenPadding()
        .padding(.bottom, AppSpacing.sm)
    }

    private var replyDraft: PostDraft {
        var draft = PostDraft(threadID: threadID, id: replyID)
        draft.body = replyText
        draft.quote = replyQuote
        return draft
    }

    private func quoteAuthor(_ quote: PostQuote) -> String {
        quote.authorDisplayName ?? quote.authorUsername.map { "@" + $0 } ?? String(localized: "profile.noName")
    }

    private func quote(_ post: ThreadPost) {
        replyQuote = PostQuote(
            postID: post.id,
            authorUsername: post.author.username,
            authorDisplayName: post.author.displayName,
            body: String(post.body.prefix(200))
        )
        isReplyFocused = true
    }

    private func load() async {
        guard let backend = environment.backend else {
            loadError = String(localized: "backend.status.notConfigured")
            return
        }
        do {
            guard let loaded = try await backend.thread(threadID) else {
                isNotFound = true
                return
            }
            let page = try await backend.threadPosts(threadID, limit: Self.pageSize)
            thread = loaded
            posts = page
            hasMore = page.count >= Self.pageSize
            loadError = nil
            seed(page)
            await loadSubscription()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadSubscription() async {
        guard session.profile != nil, let backend = environment.backend,
              let state = try? await backend.threadSubscription(threadID)
        else { return }
        isSubscribed = state
    }

    private func setSubscribed(_ value: Bool) async {
        guard let backend = environment.backend else { return }
        let previous = isSubscribed
        isSubscribed = value
        do {
            isSubscribed = try await backend.setThreadSubscription(threadID, subscribed: value)
            if value { Task { await NotificationPrimer.shared.offer() } }
        } catch {
            isSubscribed = previous
            sendError = CommunityMessage.text(for: error)
        }
    }

    private func loadMore() async {
        guard hasMore, let backend = environment.backend, let last = posts.last,
              let page = try? await backend.threadPosts(threadID, limit: Self.pageSize, after: last)
        else { return }
        let known = Set(posts.map(\.id))
        posts += page.filter { !known.contains($0.id) }
        hasMore = page.count >= Self.pageSize
        seed(page)
    }

    private func send() async {
        guard let backend = environment.backend, replyDraft.isValid else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await backend.createPost(replyDraft)
            Task { await NotificationPrimer.shared.offer() }
            replyText = ""
            replyQuote = nil
            replyID = UUID()
            sendError = nil
            // Ответивший подписан на ответы, если сам не отписывался.
            await loadSubscription()
            // Новый ответ — последний: догружаем всё после последнего показанного.
            hasMore = true
            if posts.isEmpty {
                await load()
            } else {
                await loadMore()
            }
        } catch {
            sendError = CommunityMessage.text(for: error)
        }
    }

    private func deletePost(_ post: ThreadPost) async {
        guard let backend = environment.backend else { return }
        do {
            try await backend.deletePost(post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func deleteThread() async {
        guard let backend = environment.backend else { return }
        do {
            try await backend.deleteThread(threadID)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func seed(_ page: [ThreadPost]) {
        for post in page {
            reactions.seed(ReactionKey(.post, post.id), post.reactions)
        }
    }
}

/// Ответ в обсуждении: автор, время, цитата, текст, «респект», «Ответить».
struct PostRow: View {
    let post: ThreadPost
    let canReply: Bool
    let onReply: @MainActor () -> Void
    let onDelete: @MainActor () -> Void
    /// Автора заблокировали — перечитать обсуждение.
    var onBlocked: (@MainActor () -> Void)?

    @State private var confirmsDelete = false

    var body: some View {
        CommentRow(
            author: post.isOwn ? String(localized: "report.you") : post.author.label,
            date: post.createdAt,
            text: MentionText.attributed(post.body),
            quote: post.quote.map { quote in
                MessageQuote(
                    title: quote.authorDisplayName ?? quote.authorUsername.map { "@" + $0 } ?? "",
                    text: quote.body
                )
            },
            avatar: PersonAvatar(
                name: post.author.displayName ?? post.author.username,
                path: post.author.avatarPath,
                size: CommentRowMetrics.avatarSize
            )
        ) {
            if !post.isOwn {
                ModerationMenu(target: .post, targetID: post.id, author: post.author, onBlocked: onBlocked)
            }
        } actions: {
            ReactionButton(key: ReactionKey(.post, post.id), isOwn: post.isOwn)
            if canReply {
                Button("threads.reply") { onReply() }
                    .buttonStyle(.borderless)
            }
            if post.isOwn {
                Button("threads.deletePost", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(.borderless)
            }
            if post.editedAt != nil {
                Text("reviews.edited")
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .confirmationDialog("threads.deletePostConfirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("threads.deletePost", role: .destructive) { onDelete() }
        }
    }
}
