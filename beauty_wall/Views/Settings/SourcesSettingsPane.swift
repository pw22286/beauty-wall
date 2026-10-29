import SwiftUI
import AppKit

struct SourcesSettingsPane: View {
    @EnvironmentObject private var settings: AppSettingsStore

    @SceneStorage("settings.sources.selectedPresetId") private var selectedPresetId = ""
    @State private var deletingPreset: WallpaperSourcePreset?
    @State private var isRenamingPreset = false
    @State private var renamingPresetId: String?
    @State private var renamingPresetNameDraft = ""
    private var selectedPreset: WallpaperSourcePreset? {
        settings.preset(withId: selectedPresetId) ?? settings.activePreset ?? settings.sourcePresets.first
    }

    private var selectedPresetBinding: Binding<String?> {
        Binding<String?>(
            get: { selectedPreset?.id },
            set: { selectedPresetId = $0 ?? "" }
        )
    }

    var body: some View {
        detailColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedPresetId.isEmpty {
                selectedPresetId = settings.activePreset?.id ?? settings.sourcePresets.first?.id ?? ""
            }
        }
        .onReceive(settings.$sourcePresets) { presets in
            if !presets.contains(where: { $0.id == selectedPresetId }) {
                selectedPresetId = settings.activePreset?.id ?? presets.first?.id ?? ""
            }
        }
        .alert("删除来源预设", isPresented: Binding(
            get: { deletingPreset != nil },
            set: { if !$0 { deletingPreset = nil } }
        )) {
            Button("取消", role: .cancel) { deletingPreset = nil }
            Button("删除预设", role: .destructive) {
                guard let deletingPreset else { return }
                let deleted = settings.deletePreset(id: deletingPreset.id)
                if deleted {
                    selectedPresetId = settings.activePreset?.id ?? settings.sourcePresets.first?.id ?? ""
                }
                self.deletingPreset = nil
            }
        } message: {
            if let deletingPreset {
                Text("确认删除「\(deletingPreset.name)」吗？此操作不可撤销。")
            }
        }
        .sheet(isPresented: $isRenamingPreset) {
            RenamePresetSheet(
                name: $renamingPresetNameDraft,
                onCancel: { isRenamingPreset = false },
                onConfirm: commitRename
            )
        }
    }

    private var detailColumn: some View {
        SettingsPaneScaffold(title: "来源配置", subtitle: "管理来源预设与参数，并设置生效来源") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SettingsCard("来源管理") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(settings.sourcePresets) { preset in
                            Button {
                                selectedPresetId = preset.id
                            } label: {
                                HStack(spacing: 10) {
                                    SourcePresetSidebarRow(
                                        title: settings.sourceTitle(for: preset),
                                        icon: preset.type.symbolName,
                                        statusText: statusText(for: preset),
                                        statusStyle: statusStyle(for: preset)
                                    )
                                    Spacer(minLength: 8)
                                    if selectedPreset?.id == preset.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("选择来源：\(settings.sourceTitle(for: preset))")
                        }
                    }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(WallpaperSource.allCases) { source in
                                Button {
                                    createPreset(type: source)
                                } label: {
                                    Label(source.appDisplayName, systemImage: source.symbolName)
                                }
                            }
                        } label: {
                            Label("新增来源", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("新增来源")

                        Button("重命名") {
                            beginRenameSelectedPreset()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedPreset == nil)
                        .accessibilityLabel("重命名当前来源")

                        Button("删除预设") {
                            requestDeleteSelectedPreset()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedPreset == nil || settings.sourcePresets.count <= 1)
                        .accessibilityLabel("删除当前来源预设")
                    }
                }

                if settings.sourcePresets.count > 1 {
                    SettingsRow("来源预设") {
                        Picker("", selection: selectedPresetBinding) {
                            ForEach(settings.sourcePresets) { preset in
                                Text(settings.sourceTitle(for: preset))
                                    .tag(Optional(preset.id))
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("来源预设")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Group {
                    if let preset = selectedPreset {
                        HStack(alignment: .firstTextBaseline) {
                            Text(preset.name)
                                .font(.headline)

                            Spacer(minLength: 0)

                            if settings.activeSourceId == preset.id {
                                SettingsFeedbackBanner(feedback: SettingsFeedback(tone: .success, text: "当前生效中"))
                            } else {
                                Button("设为生效") {
                                    settings.setActivePreset(id: preset.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel("设为生效来源")
                            }
                        }

                        SettingsFeedbackBanner(feedback: statusFeedback(for: preset))
                        sourceConfigDetail(for: preset)
                    } else {
                        Text("暂无来源，请先创建预设")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: SettingsLayout.sourcesDetailMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusText(for preset: WallpaperSourcePreset) -> String {
        if settings.activeSourceId == preset.id {
            return "生效中"
        }
        if settings.needsConfiguration(for: preset) {
            return "需配置"
        }
        return "就绪"
    }

    private func statusFeedback(for preset: WallpaperSourcePreset) -> SettingsFeedback {
        if settings.activeSourceId == preset.id {
            return SettingsFeedback(tone: .success, text: "状态：生效中")
        }
        if let reason = settings.unavailableReason(for: preset) {
            return SettingsFeedback(tone: .warning, text: "状态：需配置（\(reason)）")
        }
        return SettingsFeedback(tone: .neutral, text: "状态：就绪")
    }

    private func statusStyle(for preset: WallpaperSourcePreset) -> SourcePresetSidebarRow.StatusStyle {
        if settings.activeSourceId == preset.id {
            return .active
        }
        if settings.needsConfiguration(for: preset) {
            return .warning
        }
        return .normal
    }

    private func createPreset(type: WallpaperSource) {
        let preset = settings.createPreset(type: type)
        selectedPresetId = preset.id
        renamingPresetId = preset.id
        renamingPresetNameDraft = preset.name
        isRenamingPreset = true
    }

    private func beginRenameSelectedPreset() {
        guard let preset = selectedPreset else { return }
        beginRename(preset)
    }

    private func beginRename(_ preset: WallpaperSourcePreset) {
        selectedPresetId = preset.id
        renamingPresetId = preset.id
        renamingPresetNameDraft = preset.name
        isRenamingPreset = true
    }

    private func commitRename() {
        defer {
            isRenamingPreset = false
            renamingPresetId = nil
        }

        guard let renamingPresetId else { return }
        let renamed = settings.renamePreset(id: renamingPresetId, name: renamingPresetNameDraft)
        if !renamed {
            renamingPresetNameDraft = settings.preset(withId: renamingPresetId)?.name ?? renamingPresetNameDraft
        }
    }

    private func requestDeleteSelectedPreset() {
        guard let selectedPreset else { return }
        requestDelete(selectedPreset)
    }

    private func requestDelete(_ preset: WallpaperSourcePreset) {
        selectedPresetId = preset.id
        deletingPreset = preset
    }

    @ViewBuilder
    private func sourceConfigDetail(for preset: WallpaperSourcePreset) -> some View {
        switch preset.type {
        case .bing:
            bingConfigView(presetId: preset.id)
        case .nasaApod:
            nasaApodConfigView(presetId: preset.id)
        case .local:
            localConfigView(presetId: preset.id)
        case .wallhaven:
            wallhavenConfigView(presetId: preset.id)
        case .unsplash:
            unsplashConfigView(presetId: preset.id)
        }
    }

    private func bingConfigView(presetId: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("常用参数") {
                SettingsRow("地区") {
                    Picker("", selection: bingBinding(presetId: presetId, \.market)) {
                        Text("zh-CN (中国)").tag("zh-CN")
                        Text("en-US (美国)").tag("en-US")
                        Text("ja-JP (日本)").tag("ja-JP")
                    }
                    .labelsHidden()
                    .accessibilityLabel("Bing 地区")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsRow("日期偏移") {
                    TextField("0 = 今天，1 = 昨天", text: bingBinding(presetId: presetId, \.dayOffset))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Bing 日期偏移")
                }
            }

            SettingsCard("高级参数") {
                SettingsRow("候选数量") {
                    TextField("1 ~ 8", text: bingBinding(presetId: presetId, \.count))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                        .accessibilityLabel("Bing 候选数量")
                }

                SettingsHint("候选数量越大，每次随机抽取范围越广")
            }
        }
    }

    private func nasaApodConfigView(presetId: String) -> some View {
        SettingsCard("常用参数") {
            SettingsRow("优先高清图") {
                Toggle("", isOn: nasaApodBinding(presetId: presetId, \.preferHD))
                    .labelsHidden()
                    .accessibilityLabel("NASA 优先高清图")
            }

            SettingsHint("使用 NASA APOD 官方公开接口（DEMO_KEY）获取每日天文图")
        }
    }

    private func localConfigView(presetId: String) -> some View {
        let folderPath = localBinding(presetId: presetId, \.folderPath).wrappedValue

        return SettingsCard("图片目录") {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if folderPath.isEmpty {
                        Text("未选择目录")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(URL(fileURLWithPath: folderPath).lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(folderPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("选择目录") { selectLocalFolder(presetId: presetId) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("选择本地图片目录")

                if !folderPath.isEmpty {
                    Button("清空") { settings.clearLocalFolder(for: presetId) }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .accessibilityLabel("清空本地图片目录")
                }
            }

            SettingsRow("扫描子目录") {
                Toggle("", isOn: localBinding(presetId: presetId, \.includeSubdirectories))
                    .labelsHidden()
                    .accessibilityLabel("扫描子目录")
            }

            SettingsHint("支持格式：jpg / png / heic / webp / bmp / tiff / gif")
        }
    }

    private func wallhavenConfigView(presetId: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("常用参数") {
                SettingsRow("关键词") {
                    TextField("nature、anime、landscape……", text: wallhavenBinding(presetId: presetId, \.query))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Wallhaven 关键词")
                }

                SettingsRow("纯净度") {
                    Picker("", selection: wallhavenBinding(presetId: presetId, \.purity)) {
                        Text("SFW").tag("100")
                        Text("SFW + Sketchy").tag("110")
                        Text("全部").tag("111")
                    }
                    .labelsHidden()
                    .accessibilityLabel("Wallhaven 纯净度")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsRow("分类") {
                    Picker("", selection: wallhavenBinding(presetId: presetId, \.categories)) {
                        Text("全部").tag("111")
                        Text("General").tag("100")
                        Text("Anime").tag("010")
                        Text("People").tag("001")
                    }
                    .labelsHidden()
                    .accessibilityLabel("Wallhaven 分类")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsCard("高级参数") {
                SettingsRow("最低分辨率") {
                    TextField("例如 1920x1080", text: wallhavenBinding(presetId: presetId, \.atleast))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Wallhaven 最低分辨率")
                }

                SettingsRow("宽高比") {
                    TextField("例如 16x9,16x10", text: wallhavenBinding(presetId: presetId, \.ratios))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Wallhaven 宽高比")
                }
            }
        }
    }

    private func unsplashConfigView(presetId: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("常用参数") {
                SettingsRow("关键词") {
                    TextField("city、mountain、minimal……", text: unsplashBinding(presetId: presetId, \.query))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Unsplash 关键词")
                }

                SettingsRow("方向") {
                    Picker("", selection: unsplashBinding(presetId: presetId, \.orientation)) {
                        Text("横向 (landscape)").tag("landscape")
                        Text("纵向 (portrait)").tag("portrait")
                        Text("方形 (squarish)").tag("squarish")
                    }
                    .labelsHidden()
                    .accessibilityLabel("Unsplash 方向")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsCard("高级参数") {
                SettingsRow("合集 ID") {
                    TextField("多个 ID 用逗号分隔", text: unsplashBinding(presetId: presetId, \.collections))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Unsplash 合集 ID")
                }

                SettingsRow("内容过滤") {
                    Picker("", selection: unsplashBinding(presetId: presetId, \.contentFilter)) {
                        Text("低过滤 (low)").tag("low")
                        Text("高过滤 (high)").tag("high")
                    }
                    .labelsHidden()
                    .accessibilityLabel("Unsplash 内容过滤")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsRow("颜色") {
                    TextField("blue、black_and_white……", text: unsplashBinding(presetId: presetId, \.color))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Unsplash 颜色")
                }
            }
        }
    }

    private func selectLocalFolder(presetId: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择目录"
        panel.message = "选择一个包含壁纸的目录"
        if panel.runModal() == .OK, let url = panel.url {
            _ = settings.setLocalFolder(for: presetId, folderURL: url)
        }
    }

    private func wallhavenBinding(presetId: String, _ keyPath: WritableKeyPath<WallhavenConfig, String>) -> Binding<String> {
        Binding(
            get: { settings.wallhavenConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateWallhavenConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func unsplashBinding(presetId: String, _ keyPath: WritableKeyPath<UnsplashConfig, String>) -> Binding<String> {
        Binding(
            get: { settings.unsplashConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateUnsplashConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func localBinding(presetId: String, _ keyPath: WritableKeyPath<LocalFolderConfig, String>) -> Binding<String> {
        Binding(
            get: { settings.localConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateLocalConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func localBinding(presetId: String, _ keyPath: WritableKeyPath<LocalFolderConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.localConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateLocalConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func bingBinding(presetId: String, _ keyPath: WritableKeyPath<BingConfig, String>) -> Binding<String> {
        Binding(
            get: { settings.bingConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateBingConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func nasaApodBinding(presetId: String, _ keyPath: WritableKeyPath<NasaApodConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.nasaApodConfig(for: presetId)[keyPath: keyPath] },
            set: { newValue in settings.updateNasaApodConfig(for: presetId) { $0[keyPath: keyPath] = newValue } }
        )
    }
}

private struct SourcePresetSidebarRow: View {
    enum StatusStyle {
        case normal
        case warning
        case active
    }

    let title: String
    let icon: String
    let statusText: String
    let statusStyle: StatusStyle

    private var statusColor: Color {
        switch statusStyle {
        case .normal: return .secondary
        case .warning: return .orange
        case .active: return .green
        }
    }

    private var statusSymbolName: String {
        switch statusStyle {
        case .normal: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .active: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Label(statusText, systemImage: statusSymbolName)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RenamePresetSheet: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名来源")
                .font(.headline)

            TextField("输入新名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(onConfirm)
                .accessibilityLabel("来源名称")

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
