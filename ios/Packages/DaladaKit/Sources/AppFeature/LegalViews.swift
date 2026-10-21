import DaladaCore
import DesignComponents
import DesignTokens
import SwiftUI
import UserNotifications

// MARK: - Согласие

/// Согласие с условиями, правилами сообщества и политикой конфиденциальности — после входа
/// (и когда документы существенно изменились). Без согласия можно только выйти.
struct ConsentView: View {
    @Environment(SessionStore.self) private var session
    @State private var accepts = false
    @State private var error: String?

    private var language: String { PackingFormat.language }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Первый вход: дальше — username. Согласие на изменённые документы — без шагов.
                    if session.needsUsername {
                        OnboardingStepIndicator(currentStep: 1, symbols: SignUpSteps.symbols)
                            .frame(maxWidth: .infinity)
                    }
                    Text("consent.body")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Link(destination: LegalDocuments.terms(language: language)) {
                            Label("legal.terms", systemImage: "doc.text")
                        }
                        Link(destination: LegalDocuments.privacyPolicy(language: language)) {
                            Label("legal.privacy", systemImage: "lock.shield")
                        }
                    }
                    .font(AppTypography.bodyEmphasis)

                    Toggle(isOn: $accepts) {
                        Text("consent.checkbox")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .toggleStyle(.switch)

                    if let error {
                        Text(verbatim: error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                    }

                    Button {
                        Task { error = await session.acceptTerms() }
                    } label: {
                        Text("consent.continue")
                            .frame(maxWidth: .infinity)
                    }
                    .dsButton(disabled: !accepts || session.isWorking)
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.xl)
            }
            .navigationTitle("consent.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("profile.signOut") {
                        Task { await session.signOut() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Документы и поддержка

/// Ссылки на документы и поддержку, почта, версия приложения — в «Аккаунте» и «О приложении».
struct LegalLinksSection: View {
    private var language: String { PackingFormat.language }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        FormSection(
            header: String(localized: "about.title"),
            footer: String(localized: "legal.version \(version)")
        ) {
            LinkRow(
                String(localized: "legal.support"),
                icon: "questionmark.circle",
                destination: LegalDocuments.support(language: language)
            )
            LinkRow(
                String(localized: "legal.contact"),
                icon: "envelope",
                value: LegalDocuments.supportEmail,
                destination: LegalDocuments.supportMailURL
            )
            LinkRow(
                String(localized: "legal.terms"),
                icon: "doc.text",
                destination: LegalDocuments.terms(language: language)
            )
            LinkRow(
                String(localized: "legal.privacy"),
                icon: "lock.shield",
                destination: LegalDocuments.privacyPolicy(language: language)
            )
        }
    }
}

/// Строка-ссылка в стеклянной секции (DesignKit 8.0.0): значок, название, стрелка наружу.
struct LinkRow: View {
    let title: String
    let icon: String
    var value: String?
    let destination: URL

    init(_ title: String, icon: String, value: String? = nil, destination: URL) {
        self.title = title
        self.icon = icon
        self.value = value
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            UniversalRow(leadingIcon: .sfSymbol(icon, color: AppColors.accent, size: AppIconSize.lg)) {
                Text(verbatim: title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                HStack(spacing: AppSpacing.sm) {
                    if let value {
                        Text(verbatim: value)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Icon("arrow.up.right", size: AppIconSize.sm)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        // Метка ссылки не передаёт отступ разделителя наружу: значок и промежуток после него.
        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
    }
}

/// «О приложении» для гостя: поддержка и документы.
struct AboutView: View {
    var body: some View {
        ScrollView {
            LegalLinksSection()
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("about.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Уведомления

/// «Уведомления» в «Аккаунте»: включены ли, «Включить» или переход в Настройки.
struct NotificationsSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        FormSection(footer: String(localized: "notifications.footer")) {
            UniversalRow(leadingIcon: .sfSymbol("bell", color: AppColors.accent, size: AppIconSize.lg)) {
                Text("notifications.title")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                switch status {
                case .some(let current) where PushRegistrar.isAllowed(current):
                    Text("notifications.on")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                case .some(.denied):
                    Button("notifications.openSettings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderless)
                case .some:
                    Button("notifications.enable") {
                        Task {
                            await PushRegistrar.shared.requestPermissionIfNeeded()
                            await refresh()
                        }
                    }
                    .buttonStyle(.borderless)
                case nil:
                    ProgressView()
                }
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        status = await PackingReminders.authorizationStatus()
    }
}
