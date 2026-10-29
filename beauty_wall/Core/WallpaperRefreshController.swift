import Foundation
import Combine

@MainActor
final class WallpaperRefreshController: ObservableObject {
    enum RefreshTrigger {
        case manual
        case automatic
    }
    
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastStatus: String = "就绪"
    @Published private(set) var nextAutoRefreshDate: Date?
    @Published private(set) var lastRefreshDate: Date?
    
    private let settings: AppSettingsStore
    private var autoRefreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let statusTimeFormatter: DateFormatter
    
    var nextAutoRefreshDescription: String {
        guard let nextAutoRefreshDate else { return "下次自动刷新：已关闭" }
        return "下次自动刷新：\(statusTimeFormatter.string(from: nextAutoRefreshDate))"
    }
    
    var lastRefreshDescription: String {
        guard let lastRefreshDate else { return "最近刷新：--" }
        return "最近刷新：\(statusTimeFormatter.string(from: lastRefreshDate))"
    }
    
    init(settings: AppSettingsStore) {
        self.settings = settings
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        self.statusTimeFormatter = formatter
        
        settings.$autoRefreshMode
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        settings.$autoRefreshInterval
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        settings.$customAutoRefreshValue
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        settings.$customAutoRefreshUnit
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        settings.$dailyRefreshHour
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        settings.$dailyRefreshMinute
            .removeDuplicates()
            .sink { [weak self] _ in self?.rescheduleFromSettings() }
            .store(in: &cancellables)
        
        scheduleAutoRefreshTimer()
    }
    
    deinit {
        autoRefreshTimer?.invalidate()
    }
    
    func refreshNow(trigger: RefreshTrigger = .manual) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        settings.hydrateCredentialsSilentlyForRuntime()
        
        guard let activePreset = settings.activePreset else {
            lastStatus = "❌ 当前没有可用来源预设"
            return
        }
        
        print("[beauty_wall] 开始刷新 source=\(activePreset.type.displayName) preset=\(activePreset.name) targetResolution=\(settings.resolvedTargetResolutionDisplayName)")
        
        if let unavailableReason = settings.unavailableReason(for: activePreset) {
            lastStatus = "❌ \(unavailableReason)"
            return
        }
        
        guard let provider = WallpaperProviderRegistry.makeProvider(for: activePreset, settings: settings) else {
            lastStatus = "❌ 来源不可用"
            return
        }
        
        do {
            lastStatus = "正在连接 \(provider.providerName)..."
            let model = try await provider.fetchRandomWallpaper()
            let modelResolution = "\(model.width ?? 0)x\(model.height ?? 0)"
            print("[beauty_wall] 拉取完成 source=\(provider.providerName) imageId=\(model.id) resolution=\(modelResolution)")
            
            lastStatus = "正在下载并设置..."
            try await WallpaperManager.shared.downloadAndSetWallpaper(from: model)
            
            lastRefreshDate = Date()
            switch trigger {
            case .manual:
                if let width = model.width, let height = model.height {
                    lastStatus = "✅ 已手动更新：\(provider.providerName)（\(width)x\(height)）"
                } else {
                    lastStatus = "✅ 已手动更新：\(provider.providerName)"
                }
            case .automatic:
                if let width = model.width, let height = model.height {
                    lastStatus = "✅ 已自动更新：\(provider.providerName)（\(width)x\(height)）"
                } else {
                    lastStatus = "✅ 已自动更新：\(provider.providerName)"
                }
            }
        } catch {
            switch trigger {
            case .manual:
                lastStatus = "❌ 手动刷新失败：\(error.localizedDescription)"
            case .automatic:
                lastStatus = "❌ 自动刷新失败：\(error.localizedDescription)"
            }
        }
    }
    
    private func scheduleAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        
        switch settings.autoRefreshMode {
        case .interval:
            let interval = settings.resolvedAutoRefreshTimeInterval
            guard interval > 0 else {
                nextAutoRefreshDate = nil
                return
            }
            
            nextAutoRefreshDate = Date().addingTimeInterval(interval)
            
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    
                    self.nextAutoRefreshDate = Date().addingTimeInterval(self.settings.resolvedAutoRefreshTimeInterval)
                    await self.refreshNow(trigger: .automatic)
                }
            }
            
            timer.tolerance = interval * 0.1
            RunLoop.main.add(timer, forMode: .common)
            autoRefreshTimer = timer
            
        case .dailyTime:
            guard let nextDate = settings.nextDailyRefreshDate() else {
                nextAutoRefreshDate = nil
                return
            }
            
            nextAutoRefreshDate = nextDate
            
            let timer = Timer(fire: nextDate, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refreshNow(trigger: .automatic)
                    self.scheduleAutoRefreshTimer()
                }
            }
            
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            autoRefreshTimer = timer
        }
    }
    
    private func rescheduleFromSettings() {
        Task { @MainActor [weak self] in
            self?.scheduleAutoRefreshTimer()
        }
    }
}
