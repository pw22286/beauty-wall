import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var showCustomRefreshPanel = false
    @State private var customRefreshValueDraft = 2
    @State private var customRefreshUnitDraft: AutoRefreshCustomUnit = .hour
    @State private var dailyRefreshHourDraft = 8
    @State private var dailyRefreshMinuteDraft = 0
    @State private var autoRefreshFeedback: SettingsFeedback?
    @State private var resolutionFeedback: SettingsFeedback?

    private let commonAutoRefreshIntervals: [AutoRefreshInterval] = [
        .every30Minutes, .everyHour, .every2Hours,
        .every6Hours, .every12Hours, .every24Hours
    ]

    var body: some View {
        SettingsPaneScaffold(title: "通用设置", subtitle: "管理壁纸来源、刷新策略和分辨率偏好") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                sourceCard
                autoRefreshCard
                resolutionCard
            }
        }
        .onAppear {
            customRefreshValueDraft = settings.customAutoRefreshValue
            customRefreshUnitDraft = settings.customAutoRefreshUnit
            dailyRefreshHourDraft = settings.dailyRefreshHour
            dailyRefreshMinuteDraft = settings.dailyRefreshMinute
            showCustomRefreshPanel = settings.autoRefreshInterval == .custom
        }
        .onChange(of: settings.customManualResolution) { _, _ in
            resolutionFeedback = nil
        }
    }

    private var sourceCard: some View {
        SettingsCard("壁纸来源") {
            SettingsRow("当前来源") {
                Picker("", selection: Binding(
                    get: { settings.activeSourceId },
                    set: { settings.setActivePreset(id: $0) }
                )) {
                    ForEach(settings.sourcePresets) { preset in
                        Text(settings.sourceTitle(for: preset)).tag(preset.id)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("当前来源")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var autoRefreshCard: some View {
        SettingsCard("自动刷新") {
            SettingsRow("刷新模式") {
                Picker("", selection: Binding(
                    get: { settings.autoRefreshMode },
                    set: { newMode in
                        settings.setAutoRefreshMode(newMode)
                        if newMode == .dailyTime {
                            showCustomRefreshPanel = false
                        }
                        autoRefreshFeedback = SettingsFeedback(
                            tone: .neutral,
                            text: newMode == .dailyTime ? "已切换为每日定时模式" : "已切换为按间隔刷新模式"
                        )
                    }
                )) {
                    ForEach(AutoRefreshMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("刷新模式")
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
            }

            if settings.autoRefreshMode == .interval {
                SettingsRow("刷新周期") {
                    Menu {
                        refreshIntervalMenuButton(.never, title: "从不（仅手动）")
                        Divider()
                        ForEach(commonAutoRefreshIntervals, id: \.rawValue) { interval in
                            refreshIntervalMenuButton(interval, title: refreshMenuTitle(for: interval))
                        }
                        Divider()
                        Button("自定义…") {
                            customRefreshValueDraft = settings.customAutoRefreshValue
                            customRefreshUnitDraft = settings.customAutoRefreshUnit
                            showCustomRefreshPanel = true
                            autoRefreshFeedback = SettingsFeedback(tone: .neutral, text: "正在编辑自定义间隔")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(settings.autoRefreshDisplayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("刷新周期")
                }

                if showCustomRefreshPanel || settings.autoRefreshInterval == .custom {
                    SettingsRow("自定义周期") {
                        HStack(spacing: 8) {
                            Text("每隔")
                                .foregroundStyle(.secondary)

                            Stepper(value: $customRefreshValueDraft, in: 1...9999) {
                                Text("\(customRefreshValueDraft)")
                                    .font(.body.weight(.medium))
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .accessibilityLabel("自定义间隔数值")
                            .frame(width: 120)

                            Picker("", selection: $customRefreshUnitDraft) {
                                ForEach(AutoRefreshCustomUnit.allCases) { unit in
                                    Text(unit.displayName).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("自定义间隔单位")
                            .frame(width: 88)

                            Button("应用") {
                                settings.applyCustomAutoRefresh(
                                    value: customRefreshValueDraft,
                                    unit: customRefreshUnitDraft
                                )
                                autoRefreshFeedback = SettingsFeedback(
                                    tone: .success,
                                    text: "已更新为每 \(customRefreshValueDraft) \(customRefreshUnitDraft.displayName) 刷新"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                SettingsRow("执行时间") {
                    HStack(spacing: 6) {
                        Picker("", selection: $dailyRefreshHourDraft) {
                            ForEach(0..<24, id: \.self) { Text(twoDigits($0)).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityLabel("每日刷新小时")
                        .frame(width: 70)

                        Text(":")
                            .foregroundStyle(.secondary)

                        Picker("", selection: $dailyRefreshMinuteDraft) {
                            ForEach(0..<60, id: \.self) { Text(twoDigits($0)).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityLabel("每日刷新分钟")
                        .frame(width: 70)

                        Button("应用") {
                            settings.setDailyRefreshTime(
                                hour: dailyRefreshHourDraft,
                                minute: dailyRefreshMinuteDraft
                            )
                            autoRefreshFeedback = SettingsFeedback(
                                tone: .success,
                                text: "已更新每日刷新时间为 \(settings.dailyRefreshDisplayName)"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                SettingsHint("每天 \(settings.dailyRefreshDisplayName) 自动刷新一次")
            }

            if let autoRefreshFeedback {
                SettingsFeedbackBanner(feedback: autoRefreshFeedback)
            }
        }
    }

    private var resolutionCard: some View {
        SettingsCard("分辨率") {
            SettingsRow("自动适配") {
                Toggle("", isOn: $settings.enableAutoResolutionFit)
                    .labelsHidden()
                    .accessibilityLabel("自动适配分辨率")
            }

            SettingsRow("主屏分辨率") {
                Text(settings.detectedMainScreenResolutionDescription)
                    .foregroundStyle(.secondary)
            }

            SettingsRow("手动分辨率") {
                Picker("", selection: $settings.manualResolutionPreset) {
                    ForEach(ManualResolutionPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("手动分辨率")
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(settings.enableAutoResolutionFit)
                .opacity(settings.enableAutoResolutionFit ? 0.5 : 1)
            }

            if settings.enableAutoResolutionFit {
                SettingsHint("当前为自动适配模式。关闭后可手动选择分辨率。")
            }

            if !settings.enableAutoResolutionFit && settings.manualResolutionPreset == .custom {
                SettingsRow("自定义") {
                    TextField("例如 3440x1440", text: $settings.customManualResolution)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("自定义分辨率")
                        .onSubmit(validateCustomResolution)
                }
                SettingsHint("按 Return 校验格式，格式示例：3440x1440")
            }

            SettingsRow("仅 4K+") {
                Toggle("", isOn: $settings.prefer4KPlus)
                    .labelsHidden()
                    .accessibilityLabel("仅使用 4K 以上壁纸")
            }

            SettingsRow("实际请求") {
                Text(settings.resolvedTargetResolutionDisplayName)
                    .font(.body.weight(.semibold))
            }

            SettingsHint("Wallhaven 映射为 atleast；Unsplash 映射为最小宽度；Bing 使用官方接口")

            if let resolutionFeedback {
                SettingsFeedbackBanner(feedback: resolutionFeedback)
            }
        }
    }

    @ViewBuilder
    private func refreshIntervalMenuButton(_ interval: AutoRefreshInterval, title: String) -> some View {
        Button {
            settings.setAutoRefreshInterval(interval)
            if interval != .custom {
                showCustomRefreshPanel = false
            }
            autoRefreshFeedback = SettingsFeedback(tone: .success, text: "已切换刷新周期：\(title)")
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

    private func validateCustomResolution() {
        let raw = settings.customManualResolution.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = raw.range(of: #"^\d{3,5}x\d{3,5}$"#, options: .regularExpression) != nil
        resolutionFeedback = SettingsFeedback(
            tone: isValid ? .success : .warning,
            text: isValid ? "分辨率格式可用" : "格式无效，请使用 宽x高（例如 3440x1440）"
        )
    }

    private func refreshMenuTitle(for interval: AutoRefreshInterval) -> String {
        interval == .every24Hours ? "24 小时（每天一次）" : interval.displayName
    }

    private func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
