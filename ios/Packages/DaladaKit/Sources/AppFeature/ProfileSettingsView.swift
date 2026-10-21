import DaladaCore
import DesignComponents
import DesignTokens
import PhotosUI
import SwiftUI

/// Настройки профиля (нажатие на шапку в «Профиле»): фото, имя, username, зоны приватности,
/// уведомления, выход, удаление аккаунта, документы и поддержка.
struct ProfileSettingsView: View {
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var nameError: String?
    @State private var confirmsDelete = false
    @State private var deleteError: String?
    @State private var showsDeleteError = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var photoError: String?
    /// Закрытый профиль — сразу на экране, пока сервер не ответил.
    @State private var privacyOverride: Bool?
    @State private var privacyError: String?
    @State private var exportsData = false
    /// Автопауза записи поездки, минуты (0 — выключена). Настройка телефона.
    @AppStorage(AutoPauseSetting.storageKey) private var autoPauseMinutes = AutoPauseSetting.defaultMinutes

    var body: some View {
        // DesignKit 8.0.0: стеклянные секции на странице (до этого List).
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                if let profile = session.profile {
                    photoSection(profile)
                    nameSection(profile)
                }

                FormSection(footer: String(localized: "profile.settings.privacyZonesFooter")) {
                    UniversalRow(String(localized: "privacyZones.title"), icon: "house.circle", accessory: .navigation {
                        PrivacyZonesView(environment: environment)
                    })
                }

                if let profile = session.profile {
                    FormSection(footer: privacyError == nil ? String(localized: "profile.private.footer") : nil) {
                        UniversalRow(
                            String(localized: "profile.private"),
                            icon: "lock",
                            accessory: .toggle(Binding(
                                get: { privacyOverride ?? profile.isPrivate ?? false },
                                set: { value in Task { await setPrivate(value) } }
                            ))
                        )
                        .disabled(session.isWorking)
                    }
                    if let privacyError {
                        InlineStatusText(message: privacyError, type: .error)
                    }

                    FormSection(footer: String(localized: "export.data.footer")) {
                        UniversalRow(String(localized: "export.data"), icon: "square.and.arrow.down", accessory: .action {
                            exportsData = true
                        })
                    }
                }

                FormSection(footer: String(localized: "closeFriends.settingsFooter")) {
                    UniversalRow(String(localized: "closeFriends.title"), icon: "star.circle", accessory: .navigation {
                        CloseFriendsView(environment: environment)
                    })
                }

                FormSection(footer: String(localized: "notifications.settings.footer")) {
                    UniversalRow(String(localized: "notifications.title"), icon: "bell", accessory: .navigation {
                        NotificationSettingsView()
                    })
                }

                FormSection(
                    header: String(localized: "settings.recording.title"),
                    footer: String(localized: "settings.autoPause.footer")
                ) {
                    UniversalRow(
                        String(localized: "settings.autoPause"),
                        icon: "pause.circle",
                        accessory: .menu($autoPauseMinutes, options: AutoPauseSetting.options.map { minutes in
                            (
                                label: minutes == 0
                                    ? String(localized: "settings.autoPause.off")
                                    : String(localized: "settings.autoPause.minutes \(minutes)"),
                                value: minutes
                            )
                        })
                    )
                }

                FormSection {
                    UniversalRow(String(localized: "profile.signOut"), icon: "rectangle.portrait.and.arrow.right", accessory: .action {
                        Task {
                            await session.signOut()
                            dismiss()
                        }
                    })
                    .disabled(session.isWorking)
                }

                FormSection(footer: String(localized: "account.delete.footer")) {
                    if session.isWorking {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                            Text("account.delete.progress")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppSpacing.lg)
                    } else {
                        UniversalRow(String(localized: "account.delete"), icon: "trash", role: .destructive, accessory: .action {
                            confirmsDelete = true
                        })
                    }
                }

                LegalLinksSection()
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("profile.settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canSaveName {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await saveName() }
                    }
                    .disabled(session.isWorking)
                }
            }
        }
        .onAppear {
            name = session.profile?.displayName ?? ""
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await setPhoto(item) }
        }
        .onChange(of: name) { _, _ in nameError = nil }
        .sheet(isPresented: $exportsData) {
            ExportSheet(title: "export.data", footer: "export.data.sheetFooter") { progress in
                guard let backend = environment.backend else { throw URLError(.notConnectedToInternet) }
                return try await ExportFiles.archive(backend: backend, progress: progress)
            }
        }
        .confirmationDialog("account.delete.confirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("account.delete.confirmButton", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("account.delete.message")
        }
        .alert("account.delete.failed", isPresented: $showsDeleteError) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(verbatim: deleteError ?? "")
        }
    }

    // MARK: - Секции

    private func photoSection(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSection(footer: photoError == nil ? String(localized: "profile.photo.footer") : nil) {
                HStack(spacing: AppSpacing.lg) {
                    PersonAvatar(name: profile.displayName ?? profile.username, path: profile.avatarPath, size: AppIconSize.Tile.xl)
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(LocalizedStringKey(profile.avatarPath == nil ? "profile.photo.add" : "profile.photo.change"))
                        }
                        .buttonStyle(.borderless)
                        if profile.avatarPath != nil {
                            Button("profile.photo.remove", role: .destructive) {
                                Task { await removePhoto() }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .disabled(isSavingPhoto)
                    Spacer(minLength: 0)
                    if isSavingPhoto {
                        ProgressView()
                    }
                }
                .padding(.vertical, AppSpacing.lg)
            }
            if let photoError {
                InlineStatusText(message: photoError, type: .error)
            }
        }
    }

    private func nameSection(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSection(header: String(localized: "account.name")) {
                FormTextField(text: $name, placeholder: String(localized: "account.name.placeholder"), style: .row)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveName() } }
                UniversalRow(
                    String(localized: "account.username"),
                    value: profile.username.map { "@" + $0 } ?? "—"
                )
            }
            if let nameError {
                InlineStatusText(message: nameError, type: .error)
            } else if trimmedName.count > SessionStore.displayNameLimit {
                InlineStatusText(message: String(localized: "place.info.tooLong \(SessionStore.displayNameLimit)"), type: .error)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Имя изменилось, не пустое и не длиннее предела.
    private var canSaveName: Bool {
        !trimmedName.isEmpty
            && trimmedName.count <= SessionStore.displayNameLimit
            && trimmedName != (session.profile?.displayName ?? "")
    }

    private func saveName() async {
        guard canSaveName else { return }
        if let error = await session.updateDisplayName(trimmedName) {
            nameError = error
        } else {
            name = session.profile?.displayName ?? trimmedName
        }
    }

    private func setPhoto(_ item: PhotosPickerItem) async {
        isSavingPhoto = true
        photoError = nil
        defer { isSavingPhoto = false }
        guard let jpeg = await PhotoCompressor.avatar(from: item) else {
            photoError = String(localized: "photo.failed")
            return
        }
        photoError = await session.setAvatar(jpeg: jpeg)
    }

    private func removePhoto() async {
        isSavingPhoto = true
        photoError = nil
        defer { isSavingPhoto = false }
        photoError = await session.removeAvatar()
    }

    private func setPrivate(_ value: Bool) async {
        privacyOverride = value
        privacyError = await session.updateProfilePrivacy(isPrivate: value)
        privacyOverride = nil
    }

    private func deleteAccount() async {
        if let error = await session.deleteAccount() {
            deleteError = error
            showsDeleteError = true
        } else {
            dismiss()
        }
    }
}
