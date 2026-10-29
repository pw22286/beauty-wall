import Foundation

/// 统一的壁纸数据模型，各平台数据将映射为此模型
public struct WallpaperModel: Identifiable, Codable {
    public let id: String
    public let url: URL
    public let sourceName: String // e.g., "Wallhaven", "Unsplash"
    public let author: String?
    public let width: Int?
    public let height: Int?
    
    public init(id: String, url: URL, sourceName: String, author: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.url = url
        self.sourceName = sourceName
        self.author = author
        self.width = width
        self.height = height
    }
}

/// 所有支持的壁纸源都应当实现该协议
public protocol WallpaperProvider {
    /// 提取提供者的名称标识
    var providerName: String { get }
    
    /// 获取随机的壁纸信息（依据平台各自的配置策略）
    /// - Returns: 统一规范的 WallpaperModel
    func fetchRandomWallpaper() async throws -> WallpaperModel
}
