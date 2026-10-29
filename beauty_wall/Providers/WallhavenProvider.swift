import Foundation

// MARK: - API Response Model
struct WallhavenResponse: Codable {
    let data: [WallhavenImage]
}

struct WallhavenImage: Codable {
    let id: String
    let url: String // 这里通常是网页地址
    let path: String // 这个才是原图下载直链
    let resolution: String
    let file_type: String
    let file_size: Int
    // Wallhaven 可以拿到很多其他信息，如 colors, purity 等
}

// MARK: - Wallhaven Provider
public class WallhavenProvider: WallpaperProvider {
    public var providerName: String { "Wallhaven" }
    
    private let apiKey: String
    private let config: WallhavenConfig
    
    public init(apiKey: String, config: WallhavenConfig) {
        self.apiKey = apiKey
        self.config = config
    }
    
    public func fetchRandomWallpaper() async throws -> WallpaperModel {
        // Wallhaven API V1 Search
        var urlComponents = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "sorting", value: "random"),
            URLQueryItem(name: "purity", value: config.purity),
            URLQueryItem(name: "categories", value: config.categories)
        ]
        
        let trimmedQuery = config.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmedQuery))
        }
        
        let trimmedAtleast = config.atleast.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAtleast.isEmpty {
            queryItems.append(URLQueryItem(name: "atleast", value: trimmedAtleast))
        }
        
        let trimmedRatios = config.ratios.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRatios.isEmpty {
            queryItems.append(URLQueryItem(name: "ratios", value: trimmedRatios))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        print("[beauty_wall][Wallhaven] 请求URL=\(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        // 解析 JSON
        let decoded = try JSONDecoder().decode(WallhavenResponse.self, from: data)
        
        // 我们只需要第一张随机图片的 path (即真正的源图 URL)
        guard let firstImage = decoded.data.first,
              let imageUrl = URL(string: firstImage.path) else {
            // 没有搜到或者数据异常
            throw URLError(.cannotDecodeContentData)
        }
        
        // 解析一下分辨率宽和高 (可选)
        let resParts = firstImage.resolution.split(separator: "x")
        var w: Int?
        var h: Int?
        if resParts.count == 2 {
            w = Int(resParts[0])
            h = Int(resParts[1])
        }
        
        let widthText = w.map(String.init) ?? "unknown"
        let heightText = h.map(String.init) ?? "unknown"
        print("[beauty_wall][Wallhaven] 命中图片 id=\(firstImage.id) resolution=\(widthText)x\(heightText) file_size=\(firstImage.file_size)")
        
        return WallpaperModel(
            id: firstImage.id,
            url: imageUrl,
            sourceName: providerName,
            width: w,
            height: h
        )
    }
}
