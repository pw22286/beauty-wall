import Foundation

// MARK: - API Response Model
struct UnsplashResponse: Codable {
    let id: String
    let width: Int
    let height: Int
    let urls: UnsplashURLs
    let user: UnsplashUser
}

struct UnsplashURLs: Codable {
    let raw: String
    let full: String
    let regular: String
}

struct UnsplashUser: Codable {
    let name: String
    let username: String
}

// MARK: - Unsplash Provider
public class UnsplashProvider: WallpaperProvider {
    public var providerName: String { "Unsplash" }
    
    private let accessKey: String
    private let config: UnsplashConfig
    private let minimumWidth: Int
    
    public init(accessKey: String, config: UnsplashConfig, minimumWidth: Int = 0) {
        self.accessKey = accessKey
        self.config = config
        self.minimumWidth = max(0, minimumWidth)
    }
    
    public func fetchRandomWallpaper() async throws -> WallpaperModel {
        var urlComponents = URLComponents(string: "https://api.unsplash.com/photos/random")!
        
        var queryItems: [URLQueryItem] = []
        
        let trimmedQuery = config.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: trimmedQuery))
        }
        
        let trimmedOrientation = config.orientation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOrientation.isEmpty {
            queryItems.append(URLQueryItem(name: "orientation", value: trimmedOrientation))
        }
        
        let trimmedCollections = config.collections.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCollections.isEmpty {
            queryItems.append(URLQueryItem(name: "collections", value: trimmedCollections))
        }
        
        let trimmedContentFilter = config.contentFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContentFilter.isEmpty {
            queryItems.append(URLQueryItem(name: "content_filter", value: trimmedContentFilter))
        }
        
        let trimmedColor = config.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedColor.isEmpty {
            queryItems.append(URLQueryItem(name: "color", value: trimmedColor))
        }
        
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        print("[beauty_wall][Unsplash] 请求URL=\(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            // Unsplash 对于超出限额 (Rate limits) 会返回 403，这里先粗暴处理
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(UnsplashResponse.self, from: data)
        
        guard let imageUrl = buildDownloadURL(from: decoded.urls) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        print("[beauty_wall][Unsplash] 命中图片 id=\(decoded.id) resolution=\(decoded.width)x\(decoded.height) downloadURL=\(imageUrl.absoluteString)")
        
        return WallpaperModel(
            id: decoded.id,
            url: imageUrl,
            sourceName: providerName,
            author: decoded.user.name,
            width: decoded.width,
            height: decoded.height
        )
    }
    
    private func buildDownloadURL(from urls: UnsplashURLs) -> URL? {
        if var rawComponents = URLComponents(string: urls.raw) {
            var queryItems = rawComponents.queryItems ?? []
            if minimumWidth > 0 {
                queryItems.append(URLQueryItem(name: "w", value: "\(minimumWidth)"))
            }
            queryItems.append(URLQueryItem(name: "fit", value: "max"))
            queryItems.append(URLQueryItem(name: "q", value: "80"))
            rawComponents.queryItems = queryItems
            
            if let resolved = rawComponents.url {
                return resolved
            }
        }
        
        return URL(string: urls.full)
    }
}
