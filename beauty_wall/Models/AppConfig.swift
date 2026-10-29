import Foundation

public enum AutoRefreshMode: String, CaseIterable, Identifiable, Codable {
    case interval
    case dailyTime
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .interval:
            return "按间隔"
        case .dailyTime:
            return "按时间"
        }
    }
}

public enum AutoRefreshInterval: String, CaseIterable, Identifiable, Codable {
    case never
    case every30Minutes
    case everyHour
    case every2Hours
    case every6Hours
    case every12Hours
    case every24Hours
    case custom
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .never:
            return "从不（仅手动）"
        case .every30Minutes:
            return "30 分钟"
        case .everyHour:
            return "1 小时"
        case .every2Hours:
            return "2 小时"
        case .every6Hours:
            return "6 小时"
        case .every12Hours:
            return "12 小时"
        case .every24Hours:
            return "24 小时"
        case .custom:
            return "自定义"
        }
    }
    
    public func resolvedTimeInterval(customValue: Int, customUnit: AutoRefreshCustomUnit) -> TimeInterval {
        switch self {
        case .never:
            return 0
        case .every30Minutes:
            return 30 * 60
        case .everyHour:
            return 60 * 60
        case .every2Hours:
            return 2 * 60 * 60
        case .every6Hours:
            return 6 * 60 * 60
        case .every12Hours:
            return 12 * 60 * 60
        case .every24Hours:
            return 24 * 60 * 60
        case .custom:
            return customUnit.toSeconds(value: customValue)
        }
    }
}

public enum AutoRefreshCustomUnit: String, CaseIterable, Identifiable, Codable {
    case minute
    case hour
    case day
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .minute:
            return "分钟"
        case .hour:
            return "小时"
        case .day:
            return "天"
        }
    }
    
    public func toSeconds(value: Int) -> TimeInterval {
        let safeValue = max(1, value)
        switch self {
        case .minute:
            return TimeInterval(safeValue * 60)
        case .hour:
            return TimeInterval(safeValue * 60 * 60)
        case .day:
            return TimeInterval(safeValue * 24 * 60 * 60)
        }
    }
}

public enum WallpaperSource: String, CaseIterable, Identifiable, Codable {
    case bing
    case nasaApod
    case local
    case wallhaven
    case unsplash
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .bing: return "Bing"
        case .nasaApod: return "NASA APOD"
        case .local: return "本地图片"
        case .wallhaven: return "Wallhaven"
        case .unsplash: return "Unsplash"
        }
    }
    
    public var appDisplayName: String {
        switch self {
        case .bing:
            return "Bing每日精选"
        case .nasaApod:
            return "NASA APOD（每日天文图）"
        case .local:
            return "我的本地图片"
        case .wallhaven:
            return "Wallhaven (需自备 Key)"
        case .unsplash:
            return "Unsplash (需自备 Key)"
        }
    }

    public var symbolName: String {
        switch self {
        case .bing: return "globe"
        case .nasaApod: return "moon.stars"
        case .local: return "folder"
        case .wallhaven: return "photo"
        case .unsplash: return "sparkles.rectangle.stack"
        }
    }
}

public struct DisplayResolution: Codable, Hashable {
    public var width: Int
    public var height: Int
    
    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
    
    public var formatted: String {
        "\(width)x\(height)"
    }
    
    public static let fullHD = DisplayResolution(width: 1920, height: 1080)
    public static let twoK = DisplayResolution(width: 2560, height: 1440)
    public static let ultraHD = DisplayResolution(width: 3840, height: 2160)
    public static let fourKDCI = DisplayResolution(width: 4096, height: 2160)
    public static let fiveK = DisplayResolution(width: 5120, height: 2880)
    
    public static func parse(from text: String) -> DisplayResolution? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let unified = trimmed
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "X", with: "x")
            .replacingOccurrences(of: " ", with: "")
        
        let parts = unified.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        
        return DisplayResolution(width: width, height: height)
    }
}

public enum ManualResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case r1920x1080
    case r2560x1440
    case r3840x2160
    case r4096x2160
    case r5120x2880
    case custom
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .r1920x1080:
            return "1920x1080"
        case .r2560x1440:
            return "2560x1440"
        case .r3840x2160:
            return "3840x2160"
        case .r4096x2160:
            return "4096x2160"
        case .r5120x2880:
            return "5120x2880"
        case .custom:
            return "自定义"
        }
    }
    
    public var resolution: DisplayResolution? {
        switch self {
        case .r1920x1080:
            return .fullHD
        case .r2560x1440:
            return .twoK
        case .r3840x2160:
            return .ultraHD
        case .r4096x2160:
            return .fourKDCI
        case .r5120x2880:
            return .fiveK
        case .custom:
            return nil
        }
    }
}

public enum SourcePresetParams: Codable {
    case bing(BingConfig)
    case nasaApod(NasaApodConfig)
    case local(LocalFolderConfig)
    case wallhaven(WallhavenConfig)
    case unsplash(UnsplashConfig)
    
    private enum CodingKeys: String, CodingKey {
        case type
        case bing
        case nasaApod
        case local
        case wallhaven
        case unsplash
    }
    
    public var sourceType: WallpaperSource {
        switch self {
        case .bing:
            return .bing
        case .nasaApod:
            return .nasaApod
        case .local:
            return .local
        case .wallhaven:
            return .wallhaven
        case .unsplash:
            return .unsplash
        }
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceType = try container.decode(WallpaperSource.self, forKey: .type)
        
        switch sourceType {
        case .bing:
            let config = try container.decode(BingConfig.self, forKey: .bing)
            self = .bing(config)
        case .nasaApod:
            let config = try container.decode(NasaApodConfig.self, forKey: .nasaApod)
            self = .nasaApod(config)
        case .local:
            let config = try container.decode(LocalFolderConfig.self, forKey: .local)
            self = .local(config)
        case .wallhaven:
            let config = try container.decode(WallhavenConfig.self, forKey: .wallhaven)
            self = .wallhaven(config)
        case .unsplash:
            let config = try container.decode(UnsplashConfig.self, forKey: .unsplash)
            self = .unsplash(config)
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceType, forKey: .type)
        
        switch self {
        case .bing(let config):
            try container.encode(config, forKey: .bing)
        case .nasaApod(let config):
            try container.encode(config, forKey: .nasaApod)
        case .local(let config):
            try container.encode(config, forKey: .local)
        case .wallhaven(let config):
            try container.encode(config, forKey: .wallhaven)
        case .unsplash(let config):
            try container.encode(config, forKey: .unsplash)
        }
    }
}

public struct WallpaperSourcePreset: Codable, Identifiable {
    public var id: String
    public var name: String
    public var type: WallpaperSource
    public var params: SourcePresetParams
    
    public init(id: String = UUID().uuidString, name: String, type: WallpaperSource, params: SourcePresetParams) {
        self.id = id
        self.name = name
        self.type = type
        self.params = params
        self.normalizeParamsForType()
    }
    
    public var wallhavenConfig: WallhavenConfig? {
        guard case .wallhaven(let config) = params else { return nil }
        return config
    }
    
    public var bingConfig: BingConfig? {
        guard case .bing(let config) = params else { return nil }
        return config
    }

    public var nasaApodConfig: NasaApodConfig? {
        guard case .nasaApod(let config) = params else { return nil }
        return config
    }
    
    public var localConfig: LocalFolderConfig? {
        guard case .local(let config) = params else { return nil }
        return config
    }
    
    public var unsplashConfig: UnsplashConfig? {
        guard case .unsplash(let config) = params else { return nil }
        return config
    }
    
    public mutating func normalizeParamsForType() {
        guard params.sourceType != type else { return }
        
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
    }
    
    public static func `default`(for source: WallpaperSource) -> WallpaperSourcePreset {
        switch source {
        case .bing:
            return WallpaperSourcePreset(
                name: WallpaperSource.bing.appDisplayName,
                type: .bing,
                params: .bing(.default)
            )
        case .nasaApod:
            return WallpaperSourcePreset(
                name: WallpaperSource.nasaApod.appDisplayName,
                type: .nasaApod,
                params: .nasaApod(.default)
            )
        case .local:
            return WallpaperSourcePreset(
                name: "我的本地图片",
                type: .local,
                params: .local(.default)
            )
        case .wallhaven:
            return WallpaperSourcePreset(
                name: "Wallhaven 默认",
                type: .wallhaven,
                params: .wallhaven(.default)
            )
        case .unsplash:
            return WallpaperSourcePreset(
                name: "Unsplash 默认",
                type: .unsplash,
                params: .unsplash(.default)
            )
        }
    }
}

public struct BingConfig: Codable {
    public var market: String
    public var dayOffset: String
    public var count: String
    
    public static let `default` = BingConfig(
        market: "zh-CN",
        dayOffset: "0",
        count: "8"
    )
}

public struct NasaApodConfig: Codable {
    public var preferHD: Bool
    
    public static let `default` = NasaApodConfig(
        preferHD: true
    )
}

public struct LocalFolderConfig: Codable {
    public var folderPath: String
    public var includeSubdirectories: Bool
    
    public static let `default` = LocalFolderConfig(
        folderPath: "",
        includeSubdirectories: true
    )
}

public struct WallhavenConfig: Codable {
    public var query: String
    public var purity: String
    public var categories: String
    public var atleast: String
    public var ratios: String
    
    public static let `default` = WallhavenConfig(
        query: "",
        purity: "100",
        categories: "111",
        atleast: "",
        ratios: ""
    )
}

public struct UnsplashConfig: Codable {
    public var query: String
    public var orientation: String
    public var collections: String
    public var contentFilter: String
    public var color: String
    
    public static let `default` = UnsplashConfig(
        query: "",
        orientation: "landscape",
        collections: "",
        contentFilter: "low",
        color: ""
    )
}
