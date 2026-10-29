import Foundation
import AppKit
import Combine

public enum WallpaperManagerError: Error, LocalizedError {
    case invalidImageData
    case fileWriteFailed
    case workspaceSetFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidImageData: return "下载的图片数据无效"
        case .fileWriteFailed: return "无法将图片写入本地文件系统"
        case .workspaceSetFailed: return "设置系统壁纸失败"
        }
    }
}

public class WallpaperManager: ObservableObject {
    public static let shared = WallpaperManager()
    
    // 添加一个 @Published 空属性即可满足 ObservableObject 的 objectWillChange 自动生成要求
    @Published public private(set) var isReady: Bool = true
    
    private let urlSession = URLSession.shared
    
    /// 获取应用专属的图片存储目录
    private var wallpapersDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("BeautyWallpaper", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: appSupportDir.path) {
            try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        }
        return appSupportDir
    }
    
    private init() {}
    
    /// 下载图片并设置为系统桌面壁纸
    /// - Parameter model: 壁纸模型信息
    @MainActor
    public func downloadAndSetWallpaper(from model: WallpaperModel) async throws {
        if model.url.isFileURL {
            try setLocalFileWallpaper(from: model.url)
            return
        }
        
        // 1. 下载图片数据
        let (data, response) = try await urlSession.data(from: model.url)
        
        guard let httpResponse = response as? HTTPURLResponse, 
              (200...299).contains(httpResponse.statusCode),
              let _ = NSImage(data: data) else {
            throw WallpaperManagerError.invalidImageData
        }
        
        // 2. 构造本地文件路径并写入
        // 提取扩展名或默认为 jpg
        let ext = model.url.pathExtension.isEmpty ? "jpg" : model.url.pathExtension
        let fileName = "\(model.sourceName)_\(model.id).\(ext)"
        let fileURL = wallpapersDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw WallpaperManagerError.fileWriteFailed
        }
        
        // 3. 通过 NSWorkspace 设置所有的屏幕壁纸
        let workspace = NSWorkspace.shared
        let screens = NSScreen.screens
        
        for screen in screens {
            do {
                // macOS API: setDesktopImageURL
                try workspace.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                throw WallpaperManagerError.workspaceSetFailed
            }
        }
    }
    
    @MainActor
    private func setLocalFileWallpaper(from fileURL: URL) throws {
        guard let image = NSImage(contentsOf: fileURL), image.size.width > 0, image.size.height > 0 else {
            throw WallpaperManagerError.invalidImageData
        }
        
        let workspace = NSWorkspace.shared
        let screens = NSScreen.screens
        
        for screen in screens {
            do {
                try workspace.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                throw WallpaperManagerError.workspaceSetFailed
            }
        }
    }
}
