import Foundation
import Combine
import AppKit

@MainActor
final class AppSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private var isApplyingCredentialSnapshot = false
    private var localFolderBookmarks: [String: Data] = [:]
    
    @Published private(set) var sourcePresets: [WallpaperSourcePreset]
    @Published private(set) var activeSourceId: String
    
    @Published var enableAutoResolutionFit: Bool {
        didSet { saveConfig() }
    }
    
    @Published var manualResolutionPreset: ManualResolutionPreset {
        didSet { saveConfig() }
    }
    
    @Published var customManualResolution: String {
        didSet { saveConfig() }
    }
    
    @Published var prefer4KPlus: Bool {
        didSet { saveConfig() }
    }
    
    @Published var autoRefreshMode: AutoRefreshMode {
        didSet { saveConfig() }
    }
    
    @Published var autoRefreshInterval: AutoRefreshInterval {
        didSet { saveConfig() }
    }
    
    @Published var customAutoRefreshValue: Int {
        didSet {
            let clamped = min(max(customAutoRefreshValue, 1), 9999)
            if customAutoRefreshValue != clamped {
                customAutoRefreshValue = clamped
                return
            }
            saveConfig()
        }
    }
    
    @Published var customAutoRefreshUnit: AutoRefreshCustomUnit {
        didSet { saveConfig() }
    }
    
    @Published var dailyRefreshHour: Int {
        didSet {
            let clamped = min(max(dailyRefreshHour, 0), 23)
            if dailyRefreshHour != clamped {
                dailyRefreshHour = clamped
                return
            }
            saveConfig()
        }
    }
    
    @Published var dailyRefreshMinute: Int {
        didSet {
            let clamped = min(max(dailyRefreshMinute, 0), 59)
            if dailyRefreshMinute != clamped {
                dailyRefreshMinute = clamped
                return
            }
            saveConfig()
        }
    }
    
    @Published var wallhavenApiKey: String {
        didSet {
            guard !isApplyingCredentialSnapshot else { return }
            hasUnsavedCredentialChanges = true
            credentialSaveMessage = ""
        }
    }
    
    @Published var unsplashAccessKey: String {
        didSet {
            guard !isApplyingCredentialSnapshot else { return }
            hasUnsavedCredentialChanges = true
            credentialSaveMessage = ""
        }
    }
    
    @Published private(set) var hasUnsavedCredentialChanges = false
    @Published private(set) var credentialSaveMessage: String = ""

    var activePreset: WallpaperSourcePreset? {
        sourcePresets.first(where: { $0.id == activeSourceId })
    }

    var selectedSource: WallpaperSource {
        get { activePreset?.type ?? .bing }
        set { setActiveSource(newValue) }
    }
    
    var activeSourceDisplayName: String {
        guard let preset = activePreset else { return "未配置" }
        let suffix = needsConfiguration(for: preset) ? "（需配置）" : ""
        return sourceTitle(for: preset) + suffix
    }
    
    var currentFilterLevelDescription: String {
        guard let preset = activePreset else { return "未配置" }
        
        switch preset.type {
        case .bing:
            return "Bing / 每日精选"
        case .nasaApod:
            return "NASA APOD / 每日天文图"
        case .local:
            return "本地图片 / 文件夹随机"
        case .wallhaven:
            let purity = preset.wallhavenConfig?.purity ?? wallhavenConfig(for: preset.id).purity
            return "Wallhaven / \(wallhavenPurityDisplayName(purity))"
        case .unsplash:
            let contentFilter = preset.unsplashConfig?.contentFilter ?? unsplashConfig(for: preset.id).contentFilter
            return "Unsplash / \(unsplashContentFilterDisplayName(contentFilter))"
        }
    }
    
    func sourceTitle(for preset: WallpaperSourcePreset) -> String {
        if preset.name == preset.type.appDisplayName {
            return preset.name
        }
        return "\(preset.name)（\(preset.type.appDisplayName)）"
    }
    
    func needsConfiguration(for preset: WallpaperSourcePreset) -> Bool {
        unavailableReason(for: preset) != nil
    }

    func unavailableReason(for preset: WallpaperSourcePreset) -> String? {
        switch preset.type {
        case .bing:
            return nil
        case .nasaApod:
            return nil
        case .local:
            let config = preset.localConfig ?? .default
            let path = config.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return "请先选择本地图片目录" }
            
            guard let url = localFolderURL(for: preset.id) else { return "本地图片目录无效，请重新选择" }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return "本地图片目录不存在，请重新选择"
            }
            return nil
        case .wallhaven:
            return hasCredential(for: .wallhaven) ? nil : "Wallhaven 需配置 API Key"
        case .unsplash:
            return hasCredential(for: .unsplash) ? nil : "Unsplash 需配置 Access Key"
        }
    }
    
    var detectedMainScreenResolution: DisplayResolution? {
        Self.detectMainScreenResolution()
    }
    
    var detectedMainScreenResolutionDescription: String {
        guard let detected = detectedMainScreenResolution else {
            return "未检测到（将使用手动分辨率）"
        }
        return detected.formatted
    }
    
    var resolvedTargetResolution: DisplayResolution {
        let baseResolution: DisplayResolution = {
            if enableAutoResolutionFit, let detected = detectedMainScreenResolution {
                return detected
            }
            
            if let manual = resolvedManualResolution {
                return manual
            }
            
            if let detected = detectedMainScreenResolution {
                return detected
            }
            
            return .twoK
        }()
        
        guard prefer4KPlus else { return baseResolution }
        if baseResolution.width >= DisplayResolution.ultraHD.width,
           baseResolution.height >= DisplayResolution.ultraHD.height {
            return baseResolution
        }
        return .ultraHD
    }
    
    var resolvedTargetResolutionDisplayName: String {
        resolvedTargetResolution.formatted
    }
    
    var autoRefreshDisplayName: String {
        if autoRefreshMode == .dailyTime {
            return "每天 \(dailyRefreshDisplayName)"
        }
        
        if autoRefreshInterval == .custom {
            return "自定义（每 \(customAutoRefreshValue) \(customAutoRefreshUnit.displayName)）"
        }
        return autoRefreshInterval.displayName
    }
    
    var resolvedAutoRefreshTimeInterval: TimeInterval {
        autoRefreshInterval.resolvedTimeInterval(
            customValue: customAutoRefreshValue,
            customUnit: customAutoRefreshUnit
        )
    }
    
    var dailyRefreshDisplayName: String {
        String(format: "%02d:%02d", dailyRefreshHour, dailyRefreshMinute)
    }
    
    var wallhavenConfig: WallhavenConfig {
        get { wallhavenConfig(for: nil) }
        set { updateWallhavenConfig(for: nil) { $0 = newValue } }
    }
    
    var bingConfig: BingConfig {
        get { bingConfig(for: nil) }
        set { updateBingConfig(for: nil) { $0 = newValue } }
    }
    
    var nasaApodConfig: NasaApodConfig {
        get { nasaApodConfig(for: nil) }
        set { updateNasaApodConfig(for: nil) { $0 = newValue } }
    }
    
    var localConfig: LocalFolderConfig {
        get { localConfig(for: nil) }
        set { updateLocalConfig(for: nil) { $0 = newValue } }
    }
    
    var unsplashConfig: UnsplashConfig {
        get { unsplashConfig(for: nil) }
        set { updateUnsplashConfig(for: nil) { $0 = newValue } }
    }
    
    private enum Keys {
        static let sourcePresets = "app.config.sourcePresets"
        static let activeSourceId = "app.config.activeSourceId"
        static let selectedSourceLegacy = "app.config.selectedSource"
        static let enableAutoResolutionFit = "app.config.enableAutoResolutionFit"
        static let manualResolutionPreset = "app.config.manualResolutionPreset"
        static let customManualResolution = "app.config.customManualResolution"
        static let prefer4KPlus = "app.config.prefer4KPlus"
        
        static let autoRefreshMode = "app.config.autoRefreshMode"
        static let autoRefreshInterval = "app.config.autoRefreshInterval"
        static let autoRefreshCustomValue = "app.config.autoRefreshCustomValue"
        static let autoRefreshCustomUnit = "app.config.autoRefreshCustomUnit"
        static let dailyRefreshHour = "app.config.dailyRefreshHour"
        static let dailyRefreshMinute = "app.config.dailyRefreshMinute"
        
        static let wallhavenConfigLegacy = "app.config.wallhaven"
        static let unsplashConfigLegacy = "app.config.unsplash"
        static let localFolderBookmarks = "app.config.localFolderBookmarks"
        
        static let wallhavenApiKey = "app.credentials.wallhaven.apiKey.plain"
        static let unsplashAccessKey = "app.credentials.unsplash.accessKey.plain"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        let legacyWallhaven: WallhavenConfig = Self.decodeConfig(from: defaults, key: Keys.wallhavenConfigLegacy) ?? .default
        let legacyUnsplash: UnsplashConfig = Self.decodeConfig(from: defaults, key: Keys.unsplashConfigLegacy) ?? .default
        
        let storedPresets: [WallpaperSourcePreset]? = Self.decodeConfig(from: defaults, key: Keys.sourcePresets)
        let normalizedPresets = Self.normalizePresets(
            storedPresets,
            fallbackBing: .default,
            fallbackWallhaven: legacyWallhaven,
            fallbackUnsplash: legacyUnsplash
        )
        self.sourcePresets = normalizedPresets
        self.localFolderBookmarks = Self.decodeConfig(from: defaults, key: Keys.localFolderBookmarks) ?? [:]
        
        let storedActiveId = defaults.string(forKey: Keys.activeSourceId)
        let legacySelectedRaw = defaults.string(forKey: Keys.selectedSourceLegacy)
        let legacySelectedSource = WallpaperSource(rawValue: legacySelectedRaw ?? "")
        self.activeSourceId = Self.resolveActivePresetId(
            storedActiveId: storedActiveId,
            legacySelectedSource: legacySelectedSource,
            presets: normalizedPresets
        )

        let autoResolutionRaw = defaults.object(forKey: Keys.enableAutoResolutionFit) as? Bool
        self.enableAutoResolutionFit = autoResolutionRaw ?? true
        
        let manualPresetRaw = defaults.string(forKey: Keys.manualResolutionPreset)
        self.manualResolutionPreset = ManualResolutionPreset(rawValue: manualPresetRaw ?? "") ?? .r2560x1440
        
        let customManualResolution = defaults.string(forKey: Keys.customManualResolution) ?? DisplayResolution.twoK.formatted
        self.customManualResolution = customManualResolution
        
        let prefer4KPlusRaw = defaults.object(forKey: Keys.prefer4KPlus) as? Bool
        self.prefer4KPlus = prefer4KPlusRaw ?? false
        
        let modeRaw = defaults.string(forKey: Keys.autoRefreshMode)
        self.autoRefreshMode = AutoRefreshMode(rawValue: modeRaw ?? "") ?? .interval
        
        let autoRefreshRaw = defaults.string(forKey: Keys.autoRefreshInterval)
        let storedCustomValue = defaults.integer(forKey: Keys.autoRefreshCustomValue)
        let storedCustomUnitRaw = defaults.string(forKey: Keys.autoRefreshCustomUnit)
        let storedDailyHour = defaults.object(forKey: Keys.dailyRefreshHour) as? Int
        let storedDailyMinute = defaults.object(forKey: Keys.dailyRefreshMinute) as? Int
        
        let defaultCustomValue = storedCustomValue > 0 ? storedCustomValue : 2
        let defaultCustomUnit = AutoRefreshCustomUnit(rawValue: storedCustomUnitRaw ?? "") ?? .hour
        
        if let resolved = Self.resolveAutoRefresh(
            raw: autoRefreshRaw,
            defaultCustomValue: defaultCustomValue,
            defaultCustomUnit: defaultCustomUnit
        ) {
            self.autoRefreshInterval = resolved.interval
            self.customAutoRefreshValue = resolved.customValue
            self.customAutoRefreshUnit = resolved.customUnit
        } else {
            self.autoRefreshInterval = .everyHour
            self.customAutoRefreshValue = defaultCustomValue
            self.customAutoRefreshUnit = defaultCustomUnit
        }
        
        self.dailyRefreshHour = min(max(storedDailyHour ?? 8, 0), 23)
        self.dailyRefreshMinute = min(max(storedDailyMinute ?? 0, 0), 59)
        
        self.wallhavenApiKey = defaults.string(forKey: Keys.wallhavenApiKey) ?? ""
        self.unsplashAccessKey = defaults.string(forKey: Keys.unsplashAccessKey) ?? ""
        self.hasUnsavedCredentialChanges = false

        saveConfig()
    }

    func setActivePreset(id: String) {
        guard let preset = sourcePresets.first(where: { $0.id == id }) else { return }
        activeSourceId = id
        saveConfig()
    }
    
    @discardableResult
    func createPreset(type: WallpaperSource) -> WallpaperSourcePreset {
        let baseName = type.appDisplayName
        let name = uniquePresetName(base: baseName)
        
        let params: SourcePresetParams
        switch type {
        case .bing:
            params = .bing(.default)
        case .nasaApod:
            params = .nasaApod(.default)
        case .local:
            params = .local(.default)
        case .wallhaven:
            params = .wallhaven(.default)
        case .unsplash:
            params = .unsplash(.default)
        }
        
        let preset = WallpaperSourcePreset(name: name, type: type, params: params)
        sourcePresets.append(preset)
        saveConfig()
        return preset
    }
    
    @discardableResult
    func renamePreset(id: String, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = sourcePresets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        
        sourcePresets[index].name = trimmed
        saveConfig()
        return true
    }
    
    @discardableResult
    func deletePreset(id: String) -> Bool {
        guard sourcePresets.count > 1,
              let index = sourcePresets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        
        sourcePresets.remove(at: index)
        localFolderBookmarks.removeValue(forKey: id)
        
        if activeSourceId == id {
            activeSourceId = sourcePresets.first?.id ?? ""
        }
        
        saveConfig()
        return true
    }
    
    func setActiveSource(_ source: WallpaperSource) {
        guard let target = sourcePresets.first(where: { $0.type == source }) else { return }
        setActivePreset(id: target.id)
    }
    
    func presets(for source: WallpaperSource) -> [WallpaperSourcePreset] {
        sourcePresets.filter { $0.type == source }
    }

    func preset(withId presetId: String) -> WallpaperSourcePreset? {
        sourcePresets.first(where: { $0.id == presetId })
    }
    
    func wallhavenConfig(for presetId: String?) -> WallhavenConfig {
        guard let preset = resolvedPreset(presetId: presetId, source: .wallhaven) else {
            return .default
        }
        return preset.wallhavenConfig ?? .default
    }
    
    func bingConfig(for presetId: String?) -> BingConfig {
        guard let preset = resolvedPreset(presetId: presetId, source: .bing) else {
            return .default
        }
        return preset.bingConfig ?? .default
    }
    
    func nasaApodConfig(for presetId: String?) -> NasaApodConfig {
        guard let preset = resolvedPreset(presetId: presetId, source: .nasaApod) else {
            return .default
        }
        return preset.nasaApodConfig ?? .default
    }
    
    func localConfig(for presetId: String?) -> LocalFolderConfig {
        guard let preset = resolvedPreset(presetId: presetId, source: .local) else {
            return .default
        }
        return preset.localConfig ?? .default
    }
    
    func unsplashConfig(for presetId: String?) -> UnsplashConfig {
        guard let preset = resolvedPreset(presetId: presetId, source: .unsplash) else {
            return .default
        }
        return preset.unsplashConfig ?? .default
    }
    
    func updateWallhavenConfig(for presetId: String?, mutate: (inout WallhavenConfig) -> Void) {
        updatePreset(source: .wallhaven, presetId: presetId) { preset in
            var config = preset.wallhavenConfig ?? .default
            mutate(&config)
            preset.params = .wallhaven(config)
        }
    }
    
    func updateBingConfig(for presetId: String?, mutate: (inout BingConfig) -> Void) {
        updatePreset(source: .bing, presetId: presetId) { preset in
            var config = preset.bingConfig ?? .default
            mutate(&config)
            preset.params = .bing(config)
        }
    }
    
    func updateNasaApodConfig(for presetId: String?, mutate: (inout NasaApodConfig) -> Void) {
        updatePreset(source: .nasaApod, presetId: presetId) { preset in
            var config = preset.nasaApodConfig ?? .default
            mutate(&config)
            preset.params = .nasaApod(config)
        }
    }
    
    func updateLocalConfig(for presetId: String?, mutate: (inout LocalFolderConfig) -> Void) {
        updatePreset(source: .local, presetId: presetId) { preset in
            var config = preset.localConfig ?? .default
            mutate(&config)
            preset.params = .local(config)
        }
    }
    
    @discardableResult
    func setLocalFolder(for presetId: String, folderURL: URL) -> Bool {
        guard sourcePresets.contains(where: { $0.id == presetId && $0.type == .local }) else { return false }
        
        let bookmarkData: Data?
        do {
            bookmarkData = try folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmarkData = nil
        }
        
        updateLocalConfig(for: presetId) { config in
            config.folderPath = folderURL.path
        }
        
        if let bookmarkData {
            localFolderBookmarks[presetId] = bookmarkData
            saveLocalFolderBookmarks()
        }
        
        return true
    }
    
    func clearLocalFolder(for presetId: String) {
        guard sourcePresets.contains(where: { $0.id == presetId && $0.type == .local }) else { return }
        updateLocalConfig(for: presetId) { config in
            config.folderPath = ""
        }
        localFolderBookmarks.removeValue(forKey: presetId)
        saveLocalFolderBookmarks()
    }
    
    func localFolderURL(for presetId: String?) -> URL? {
        guard let preset = resolvedPreset(presetId: presetId, source: .local) else { return nil }
        
        let config = preset.localConfig ?? .default
        let path = config.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return nil }
        
        if let bookmarkData = localFolderBookmarks[preset.id] {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    localFolderBookmarks[preset.id] = nil
                    saveLocalFolderBookmarks()
                }
                return resolvedURL
            }
        }
        
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    
    func updateUnsplashConfig(for presetId: String?, mutate: (inout UnsplashConfig) -> Void) {
        updatePreset(source: .unsplash, presetId: presetId) { preset in
            var config = preset.unsplashConfig ?? .default
            mutate(&config)
            preset.params = .unsplash(config)
        }
    }
    
    func setAutoRefreshInterval(_ interval: AutoRefreshInterval) {
        autoRefreshMode = .interval
        autoRefreshInterval = interval
    }
    
    func setAutoRefreshMode(_ mode: AutoRefreshMode) {
        autoRefreshMode = mode
    }
    
    func applyCustomAutoRefresh(value: Int, unit: AutoRefreshCustomUnit) {
        customAutoRefreshValue = min(max(value, 1), 9999)
        customAutoRefreshUnit = unit
        autoRefreshMode = .interval
        autoRefreshInterval = .custom
    }
    
    func setDailyRefreshTime(hour: Int, minute: Int) {
        dailyRefreshHour = min(max(hour, 0), 23)
        dailyRefreshMinute = min(max(minute, 0), 59)
    }
    
    func nextDailyRefreshDate(from reference: Date = Date()) -> Date? {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "zh_CN")
        
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = dailyRefreshHour
        components.minute = dailyRefreshMinute
        components.second = 0
        
        guard var targetDate = calendar.date(from: components) else { return nil }
        if targetDate <= reference {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        }
        return targetDate
    }
    
    func credential(for source: WallpaperSource) -> String? {
        guard sourceRequiresCredential(source) else { return nil }
        
        let raw: String
        switch source {
        case .bing:
            raw = ""
        case .nasaApod:
            raw = ""
        case .local:
            raw = ""
        case .wallhaven:
            raw = wallhavenApiKey
        case .unsplash:
            raw = unsplashAccessKey
        }
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    func hasCredential(for source: WallpaperSource) -> Bool {
        guard sourceRequiresCredential(source) else { return true }
        return credential(for: source) != nil
    }
    
    func effectiveWallhavenAtleast(for config: WallhavenConfig) -> String {
        let manualAtleast = config.atleast.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualAtleast.isEmpty {
            return manualAtleast
        }
        return resolvedTargetResolution.formatted
    }
    
    func effectiveUnsplashMinimumWidth() -> Int {
        resolvedTargetResolution.width
    }
    
    func saveCredentialsToKeychain() {
        defaults.set(wallhavenApiKey, forKey: Keys.wallhavenApiKey)
        defaults.set(unsplashAccessKey, forKey: Keys.unsplashAccessKey)
        hasUnsavedCredentialChanges = false
        credentialSaveMessage = "✅ 凭证已保存"
    }
    
    func loadCredentialsFromKeychainByUser() {
        let wallhaven = defaults.string(forKey: Keys.wallhavenApiKey) ?? ""
        let unsplash = defaults.string(forKey: Keys.unsplashAccessKey) ?? ""
        
        applyCredentialSnapshot(wallhavenApiKey: wallhaven, unsplashAccessKey: unsplash, message: nil)
        
        if hasCredential(for: .wallhaven) || hasCredential(for: .unsplash) {
            credentialSaveMessage = "✅ 已读取已保存凭证"
        } else {
            credentialSaveMessage = "⚠️ 本地暂无已保存凭证"
        }
    }
    
    func hydrateCredentialsSilentlyForRuntime() {
    }

    private func resolvedPreset(presetId: String?, source: WallpaperSource) -> WallpaperSourcePreset? {
        if let presetId,
           let preset = sourcePresets.first(where: { $0.id == presetId && $0.type == source }) {
            return preset
        }
        
        if activePreset?.type == source {
            return activePreset
        }
        
        return sourcePresets.first(where: { $0.type == source })
    }
    
    private func updatePreset(source: WallpaperSource, presetId: String?, mutate: (inout WallpaperSourcePreset) -> Void) {
        let targetId: String? = {
            if let presetId,
               sourcePresets.contains(where: { $0.id == presetId && $0.type == source }) {
                return presetId
            }
            
            if let activePreset, activePreset.type == source {
                return activePreset.id
            }
            
            return sourcePresets.first(where: { $0.type == source })?.id
        }()
        
        guard let targetId,
              let index = sourcePresets.firstIndex(where: { $0.id == targetId }) else { return }
        
        var updated = sourcePresets[index]
        mutate(&updated)
        updated.normalizeParamsForType()
        sourcePresets[index] = updated
        saveConfig()
    }
    
    private func saveConfig() {
        defaults.set(activeSourceId, forKey: Keys.activeSourceId)
        Self.encodeConfig(sourcePresets, to: defaults, key: Keys.sourcePresets)
        
        defaults.set(selectedSource.rawValue, forKey: Keys.selectedSourceLegacy)
        Self.encodeConfig(wallhavenConfig(for: nil), to: defaults, key: Keys.wallhavenConfigLegacy)
        Self.encodeConfig(unsplashConfig(for: nil), to: defaults, key: Keys.unsplashConfigLegacy)
        
        defaults.set(enableAutoResolutionFit, forKey: Keys.enableAutoResolutionFit)
        defaults.set(manualResolutionPreset.rawValue, forKey: Keys.manualResolutionPreset)
        defaults.set(customManualResolution, forKey: Keys.customManualResolution)
        defaults.set(prefer4KPlus, forKey: Keys.prefer4KPlus)
        
        defaults.set(autoRefreshMode.rawValue, forKey: Keys.autoRefreshMode)
        defaults.set(autoRefreshInterval.rawValue, forKey: Keys.autoRefreshInterval)
        defaults.set(customAutoRefreshValue, forKey: Keys.autoRefreshCustomValue)
        defaults.set(customAutoRefreshUnit.rawValue, forKey: Keys.autoRefreshCustomUnit)
        defaults.set(dailyRefreshHour, forKey: Keys.dailyRefreshHour)
        defaults.set(dailyRefreshMinute, forKey: Keys.dailyRefreshMinute)

        saveLocalFolderBookmarks()
    }
    
    private func saveLocalFolderBookmarks() {
        Self.encodeConfig(localFolderBookmarks, to: defaults, key: Keys.localFolderBookmarks)
    }
    
    private func applyCredentialSnapshot(wallhavenApiKey: String, unsplashAccessKey: String, message: String?) {
        isApplyingCredentialSnapshot = true
        self.wallhavenApiKey = wallhavenApiKey
        self.unsplashAccessKey = unsplashAccessKey
        isApplyingCredentialSnapshot = false
        
        hasUnsavedCredentialChanges = false
        credentialSaveMessage = message ?? ""
    }
    
    private static func resolveActivePresetId(
        storedActiveId: String?,
        legacySelectedSource: WallpaperSource?,
        presets: [WallpaperSourcePreset]
    ) -> String {
        if let storedActiveId,
           presets.contains(where: { $0.id == storedActiveId }) {
            return storedActiveId
        }
        
        if let legacySelectedSource,
           let legacyPreset = presets.first(where: { $0.type == legacySelectedSource }) {
            return legacyPreset.id
        }
        
        return presets.first?.id ?? ""
    }
    
    private static func normalizePresets(
        _ presets: [WallpaperSourcePreset]?,
        fallbackBing: BingConfig,
        fallbackWallhaven: WallhavenConfig,
        fallbackUnsplash: UnsplashConfig
    ) -> [WallpaperSourcePreset] {
        var normalized: [WallpaperSourcePreset] = []
        var usedIds = Set<String>()
        
        if let presets {
            for var preset in presets {
                if preset.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || usedIds.contains(preset.id) {
                    preset.id = UUID().uuidString
                }
                
                if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    preset.name = preset.type.appDisplayName
                } else if isLegacyDefaultPresetName(preset.name, for: preset.type) {
                    preset.name = preset.type.appDisplayName
                }
                
                preset.normalizeParamsForType()
                normalized.append(preset)
                usedIds.insert(preset.id)
            }
        }
        
        if presets == nil {
            normalized = [
                WallpaperSourcePreset(
                    name: WallpaperSource.bing.appDisplayName,
                    type: .bing,
                    params: .bing(fallbackBing)
                ),
                WallpaperSourcePreset(
                    name: WallpaperSource.nasaApod.appDisplayName,
                    type: .nasaApod,
                    params: .nasaApod(.default)
                ),
                WallpaperSourcePreset(
                    name: WallpaperSource.wallhaven.appDisplayName,
                    type: .wallhaven,
                    params: .wallhaven(fallbackWallhaven)
                ),
                WallpaperSourcePreset(
                    name: WallpaperSource.unsplash.appDisplayName,
                    type: .unsplash,
                    params: .unsplash(fallbackUnsplash)
                )
            ]
        } else if normalized.isEmpty {
            normalized = [
                WallpaperSourcePreset(
                    name: WallpaperSource.bing.appDisplayName,
                    type: .bing,
                    params: .bing(fallbackBing)
                )
            ]
        }
        
        if !normalized.contains(where: { $0.type == .bing }) {
            normalized.insert(
                WallpaperSourcePreset(
                    name: WallpaperSource.bing.appDisplayName,
                    type: .bing,
                    params: .bing(fallbackBing)
                ),
                at: 0
            )
        }
        
        if !normalized.contains(where: { $0.type == .nasaApod }) {
            normalized.insert(
                WallpaperSourcePreset(
                    name: WallpaperSource.nasaApod.appDisplayName,
                    type: .nasaApod,
                    params: .nasaApod(.default)
                ),
                at: min(1, normalized.count)
            )
        }
        
        if !normalized.contains(where: { $0.type == .local }) {
            normalized.insert(
                WallpaperSourcePreset(
                    name: "我的本地图片",
                    type: .local,
                    params: .local(.default)
                ),
                at: min(2, normalized.count)
            )
        }
        
        return normalized
    }
    
    private static func isLegacyDefaultPresetName(_ name: String, for source: WallpaperSource) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .bing:
            return trimmed == "Bing 默认" || trimmed == "每日精选 (Bing)"
        case .nasaApod:
            return trimmed == "NASA 默认" || trimmed == "NASA APOD 默认"
        case .local:
            return trimmed == "本地图片 默认"
        case .wallhaven:
            return trimmed == "Wallhaven 默认"
        case .unsplash:
            return trimmed == "Unsplash 默认"
        }
    }
    
    private func uniquePresetName(base: String) -> String {
        let existingNames = Set(sourcePresets.map(\.name))
        if !existingNames.contains(base) {
            return base
        }
        
        for index in 2...999 {
            let candidate = "\(base) \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }
        
        return "\(base) \(Int.random(in: 1000...9999))"
    }
    
    private var resolvedManualResolution: DisplayResolution? {
        if manualResolutionPreset == .custom {
            return DisplayResolution.parse(from: customManualResolution)
        }
        return manualResolutionPreset.resolution
    }
    
    private static func detectMainScreenResolution() -> DisplayResolution? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }
        
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        guard width > 0, height > 0 else { return nil }
        return DisplayResolution(width: width, height: height)
    }
    
    private func wallhavenPurityDisplayName(_ purity: String) -> String {
        switch purity {
        case "100":
            return "SFW"
        case "110":
            return "SFW + Sketchy"
        case "111":
            return "全部"
        default:
            return purity
        }
    }
    
    private func unsplashContentFilterDisplayName(_ contentFilter: String) -> String {
        switch contentFilter.lowercased() {
        case "high":
            return "高过滤"
        case "low":
            return "低过滤"
        default:
            return contentFilter
        }
    }
    
    private func sourceRequiresCredential(_ source: WallpaperSource) -> Bool {
        switch source {
        case .bing, .nasaApod, .local:
            return false
        case .wallhaven, .unsplash:
            return true
        }
    }
    
    private static func resolveAutoRefresh(
        raw: String?,
        defaultCustomValue: Int,
        defaultCustomUnit: AutoRefreshCustomUnit
    ) -> (interval: AutoRefreshInterval, customValue: Int, customUnit: AutoRefreshCustomUnit)? {
        guard let raw else {
            return nil
        }
        
        if let interval = AutoRefreshInterval(rawValue: raw) {
            return (interval, defaultCustomValue, defaultCustomUnit)
        }
        
        switch raw {
        case "every1Minute":
            return (.custom, 1, .minute)
        case "every3Minutes":
            return (.custom, 3, .minute)
        case "every5Minutes":
            return (.custom, 5, .minute)
        case "every10Minutes":
            return (.custom, 10, .minute)
        case "every15Minutes":
            return (.custom, 15, .minute)
        case "everyWeek":
            return (.custom, 7, .day)
        case "everyMonth":
            return (.custom, 30, .day)
        default:
            return nil
        }
    }
    
    private static func decodeConfig<T: Decodable>(from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    private static func encodeConfig<T: Encodable>(_ value: T, to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
