import Foundation

protocol WallpaperProviderFactory {
    var source: WallpaperSource { get }
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)?
}

struct BingProviderFactory: WallpaperProviderFactory {
    let source: WallpaperSource = .bing
    
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        let config = preset.bingConfig ?? .default
        print("[beauty_wall][Bing] 预设=\(preset.name) market=\(config.market) dayOffset=\(config.dayOffset) count=\(config.count)")
        return BingProvider(config: config)
    }
}

struct NasaApodProviderFactory: WallpaperProviderFactory {
    let source: WallpaperSource = .nasaApod
    
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        let config = preset.nasaApodConfig ?? .default
        print("[beauty_wall][NASA] 预设=\(preset.name) preferHD=\(config.preferHD)")
        return NasaApodProvider(config: config)
    }
}

struct LocalFolderProviderFactory: WallpaperProviderFactory {
    let source: WallpaperSource = .local
    
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        let config = preset.localConfig ?? .default
        let folderURL = settings.localFolderURL(for: preset.id)
        print("[beauty_wall][Local] 预设=\(preset.name) folder=\(config.folderPath) includeSubdirectories=\(config.includeSubdirectories)")
        return LocalFolderProvider(folderURL: folderURL, config: config)
    }
}

struct WallhavenProviderFactory: WallpaperProviderFactory {
    let source: WallpaperSource = .wallhaven
    
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        guard let apiKey = settings.credential(for: .wallhaven) else { return nil }
        var config = preset.wallhavenConfig ?? .default
        config.atleast = settings.effectiveWallhavenAtleast(for: config)
        print("[beauty_wall][Wallhaven] 预设=\(preset.name) atleast=\(config.atleast) purity=\(config.purity) categories=\(config.categories)")
        return WallhavenProvider(apiKey: apiKey, config: config)
    }
}

struct UnsplashProviderFactory: WallpaperProviderFactory {
    let source: WallpaperSource = .unsplash
    
    func makeProvider(from preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        guard let accessKey = settings.credential(for: .unsplash) else { return nil }
        let config = preset.unsplashConfig ?? .default
        let minimumWidth = settings.effectiveUnsplashMinimumWidth()
        print("[beauty_wall][Unsplash] 预设=\(preset.name) minimumWidth=\(minimumWidth) orientation=\(config.orientation) content_filter=\(config.contentFilter)")
        return UnsplashProvider(
            accessKey: accessKey,
            config: config,
            minimumWidth: minimumWidth
        )
    }
}

enum WallpaperProviderRegistry {
    static let factories: [WallpaperSource: any WallpaperProviderFactory] = [
        .bing: BingProviderFactory(),
        .nasaApod: NasaApodProviderFactory(),
        .local: LocalFolderProviderFactory(),
        .wallhaven: WallhavenProviderFactory(),
        .unsplash: UnsplashProviderFactory()
    ]
    
    static func makeProvider(for preset: WallpaperSourcePreset, settings: AppSettingsStore) -> (any WallpaperProvider)? {
        factories[preset.type]?.makeProvider(from: preset, settings: settings)
    }
}
