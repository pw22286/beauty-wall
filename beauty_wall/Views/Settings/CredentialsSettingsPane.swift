import SwiftUI
import AppKit

struct CredentialsSettingsPane: View {
    @EnvironmentObject private var settings: AppSettingsStore

    private var saveFeedback: SettingsFeedback {
        if settings.hasUnsavedCredentialChanges {
            return SettingsFeedback(tone: .warning, text: "有未保存修改")
        }

        let message = settings.credentialSaveMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return SettingsFeedback(tone: .neutral, text: "尚未修改凭证")
        }

        if message.hasPrefix("✅") {
            return SettingsFeedback(tone: .success, text: normalizeCredentialMessage(message, prefix: "✅"))
        }
        if message.hasPrefix("⚠️") {
            return SettingsFeedback(tone: .warning, text: normalizeCredentialMessage(message, prefix: "⚠️"))
        }
        if message.hasPrefix("❌") {
            return SettingsFeedback(tone: .error, text: normalizeCredentialMessage(message, prefix: "❌"))
        }

        return SettingsFeedback(tone: .neutral, text: message)
    }

    var body: some View {
        SettingsPaneScaffold(title: "凭证管理", subtitle: "保存 Wallhaven / Unsplash 的访问凭证") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                wallhavenCredentialCard
                unsplashCredentialCard

                SettingsHint("Bing / NASA APOD / 本地图片无需 Key")

                HStack(spacing: 10) {
                    Button("保存凭证") { settings.saveCredentialsToKeychain() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)

                    Button("读取已保存") { settings.loadCredentialsFromKeychainByUser() }
                        .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }

                SettingsFeedbackBanner(feedback: saveFeedback)
            }
        }
    }

    private var wallhavenCredentialCard: some View {
        SettingsCard("Wallhaven") {
            SettingsRow("API Key") {
                SecureField("输入 Wallhaven API Key", text: $settings.wallhavenApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Wallhaven API Key")
            }

            credentialStatus(for: .wallhaven)

            Button("获取 Key") { openURL("https://wallhaven.cc/settings/account") }
                .buttonStyle(.bordered)
                .accessibilityLabel("打开 Wallhaven Key 页面")
        }
    }

    private var unsplashCredentialCard: some View {
        SettingsCard("Unsplash") {
            SettingsRow("Access Key") {
                SecureField("输入 Unsplash Access Key", text: $settings.unsplashAccessKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Unsplash Access Key")
            }

            credentialStatus(for: .unsplash)

            Button("获取 Key") { openURL("https://unsplash.com/oauth/applications") }
                .buttonStyle(.bordered)
                .accessibilityLabel("打开 Unsplash Key 页面")

            SettingsHint("MVP 阶段仅需 Access Key")
        }
    }

    @ViewBuilder
    private func credentialStatus(for source: WallpaperSource) -> some View {
        if settings.hasCredential(for: source) {
            SettingsFeedbackBanner(feedback: SettingsFeedback(tone: .success, text: "已配置"))
        } else {
            SettingsFeedbackBanner(feedback: SettingsFeedback(tone: .warning, text: "未配置，填写后使用"))
        }
    }

    private func normalizeCredentialMessage(_ text: String, prefix: String) -> String {
        text.replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}
