import Foundation

public enum LocalFolderProviderError: Error, LocalizedError {
    case folderNotConfigured
    case folderNotFound
    case noSupportedImages
    
    public var errorDescription: String? {
        switch self {
        case .folderNotConfigured:
            return "请先配置本地图片目录"
        case .folderNotFound:
            return "本地图片目录不存在或无法访问"
        case .noSupportedImages:
            return "目录内未找到可用图片（支持 jpg/png/heic/webp 等）"
        }
    }
}

public final class LocalFolderProvider: WallpaperProvider {
    public var providerName: String { "本地图片" }
    
    private let folderURL: URL?
    private let config: LocalFolderConfig
    private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "bmp", "tif", "tiff", "gif"
    ]
    
    public init(folderURL: URL?, config: LocalFolderConfig) {
        self.folderURL = folderURL
        self.config = config
    }
    
    public func fetchRandomWallpaper() async throws -> WallpaperModel {
        guard let folderURL else {
            throw LocalFolderProviderError.folderNotConfigured
        }
        
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalFolderProviderError.folderNotFound
        }
        
        let imageFiles = try collectImageFiles(in: folderURL, includeSubdirectories: config.includeSubdirectories)
        guard let selected = imageFiles.randomElement() else {
            throw LocalFolderProviderError.noSupportedImages
        }
        
        let imageId = selected.path.replacingOccurrences(of: "/", with: "_")
        print("[beauty_wall][Local] 命中图片 id=\(imageId) path=\(selected.path)")
        
        return WallpaperModel(
            id: imageId,
            url: selected,
            sourceName: providerName
        )
    }
    
    private func collectImageFiles(in folderURL: URL, includeSubdirectories: Bool) throws -> [URL] {
        if includeSubdirectories {
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }
            
            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                if isSupportedImageFile(fileURL) {
                    urls.append(fileURL)
                }
            }
            return urls
        } else {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
                options: [.skipsHiddenFiles]
            )
            return urls.filter(isSupportedImageFile(_:))
        }
    }
    
    private func isSupportedImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { return false }
        
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? false
    }
}
