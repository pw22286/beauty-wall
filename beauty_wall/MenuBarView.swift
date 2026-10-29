import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var refreshController: WallpaperRefreshController
    @Environment(\.openWindow) private var openWindow

    private let commonAutoRefreshIntervals: [AutoRefreshInterval] = [
        .every30Minutes, .everyHour, .every2Hours,
        .every6Hours, .every12Hours, .every24Hours
    ]

    private var refreshStatusFeedback: SettingsFeedback {
        if refreshController.isRefreshing {
            return SettingsFeedback(tone: .neutral, text: "正在刷新壁纸…")
        }

        let raw = refreshController.lastStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return SettingsFeedback(tone: .neutral, text: "等待下一次刷新")
        }

        if raw.hasPrefix("✅") {
            return SettingsFeedback(tone: .success, text: normalizeStatusText(raw, prefix: "✅"))
        }
        if raw.hasPrefix("❌") {
            return SettingsFeedback(tone: .error, text: normalizeStatusText(raw, prefix: "❌"))
        }
        if raw.hasPrefix("⚠️") {
            return SettingsFeedback(tone: .warning, text: normalizeStatusText(raw, prefix: "⚠️"))
        }

        return SettingsFeedback(tone: .neutral, text: raw)
    }

    var body: some View {
        Group {
            statusSection
            Divider()
            sourceSection
            Divider()
            refreshSection
            Divider()
            actionSection
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuStatusLine(
                systemImage: "photo.on.rectangle.angled",
                text: "当前来源：\(settings.activeSourceDisplayName)",
                tone: .neutral
            )

            MenuStatusLine(
                systemImage: "clock",
                text: refreshController.nextAutoRefreshDescription,
                tone: .neutral
            )

            MenuStatusLine(
                systemImage: refreshStatusFeedback.tone.symbolName,
                text: refreshStatusFeedback.text,
                tone: refreshStatusFeedback.tone
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceSection: some View {
        Menu("切换来源") {
            ForEach(settings.sourcePresets) { preset in
                Button {
                    settings.setActivePreset(id: preset.id)
                } label: {
                    HStack {
                        let suffix = settings.needsConfiguration(for: preset) ? " （需配置）" : ""
                        Text(menuSafeTitle(settings.sourceTitle(for: preset) + suffix))
                        Spacer(minLength: 8)
                        if settings.activeSourceId == preset.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .accessibilityLabel("切换来源")
    }

    private var refreshSection: some View {
        Menu("自动刷新周期") {
            refreshIntervalButton(.never, title: "从不（仅手动）")
            Divider()
            ForEach(commonAutoRefreshIntervals, id: \.rawValue) { interval in
                refreshIntervalButton(interval, title: refreshMenuTitle(for: interval))
            }
            Divider()
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Text("自定义 / 高级...")
                    Spacer(minLength: 8)
                    if settings.autoRefreshMode == .dailyTime || settings.autoRefreshInterval == .custom {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .accessibilityLabel("自动刷新周期")
    }

    private var actionSection: some View {
        Group {
            Button(refreshController.isRefreshing ? "正在刷新..." : "立即刷新壁纸") {
                Task { await refreshController.refreshNow(trigger: .manual) }
            }
            .disabled(refreshController.isRefreshing)
            .accessibilityLabel("立即刷新壁纸")

            Button("打开设置…") {
                openSettingsWindow()
            }
            .accessibilityLabel("打开设置")

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .accessibilityLabel("退出应用")
        }
    }

    @ViewBuilder
    private func refreshIntervalButton(_ interval: AutoRefreshInterval, title: String) -> some View {
        Button {
            settings.setAutoRefreshInterval(interval)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                if settings.autoRefreshMode == .interval && settings.autoRefreshInterval == interval {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func refreshMenuTitle(for interval: AutoRefreshInterval) -> String {
        interval == .every24Hours ? "24 小时（每天一次）" : interval.displayName
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func normalizeStatusText(_ raw: String, prefix: String) -> String {
        raw.replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func menuSafeTitle(_ text: String, maxLength: Int = 30) -> String {
        guard text.count > maxLength, maxLength > 3 else { return text }
        return String(text.prefix(maxLength - 3)) + "..."
    }
}

private struct MenuStatusLine: View {
    let systemImage: String
    let text: String
    let tone: SettingsFeedbackTone

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tone.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(text)
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(AppSettingsStore())
            .environmentObject(WallpaperRefreshController(settings: AppSettingsStore()))
    }
}
