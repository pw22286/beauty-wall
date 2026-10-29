import Foundation

private struct NasaApodItem: Codable {
    let date: String?
    let title: String?
    let mediaType: String?
    let url: String?
    let hdurl: String?
    let copyright: String?
    
    enum CodingKeys: String, CodingKey {
        case date
        case title
        case mediaType = "media_type"
        case url
        case hdurl
        case copyright
    }
}

private struct NasaApodErrorPayload: Codable {
    let code: Int?
    let msg: String?
}

public enum NasaApodProviderError: Error, LocalizedError {
    case apiError(String)
    case noImageResult
    case invalidImageURL
    
    public var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "NASA APOD 请求失败：\(message)"
        case .noImageResult:
            return "NASA APOD 暂无可用图片"
        case .invalidImageURL:
            return "NASA APOD 返回了无效图片地址"
        }
    }
}

public final class NasaApodProvider: WallpaperProvider {
    public var providerName: String { "NASA APOD" }
    
    private let config: NasaApodConfig
    
    public init(config: NasaApodConfig) {
        self.config = config
    }
    
    public func fetchRandomWallpaper() async throws -> WallpaperModel {
        var components = URLComponents(string: "https://api.nasa.gov/planetary/apod")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: "DEMO_KEY"),
            URLQueryItem(name: "count", value: "10")
        ]
        
        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }
        
        print("[beauty_wall][NASA] 请求URL=\(requestURL.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let apiMessage = (try? JSONDecoder().decode(NasaApodErrorPayload.self, from: data).msg) ?? "HTTP \(httpResponse.statusCode)"
            throw NasaApodProviderError.apiError(apiMessage)
        }
        
        let items = try decodeItems(from: data)
        let imageItems = items.filter { ($0.mediaType ?? "").lowercased() == "image" }
        guard let selected = imageItems.randomElement() else {
            throw NasaApodProviderError.noImageResult
        }
        
        let urlString = config.preferHD ? (selected.hdurl ?? selected.url) : (selected.url ?? selected.hdurl)
        guard let urlString, let imageURL = URL(string: urlString) else {
            throw NasaApodProviderError.invalidImageURL
        }
        
        let imageId = (selected.date?.isEmpty == false ? selected.date! : imageURL.lastPathComponent)
            .replacingOccurrences(of: "/", with: "-")
        
        print("[beauty_wall][NASA] 命中图片 id=\(imageId) title=\(selected.title ?? "-") preferHD=\(config.preferHD)")
        
        return WallpaperModel(
            id: "nasa_\(imageId)",
            url: imageURL,
            sourceName: providerName,
            author: selected.copyright
        )
    }
    
    private func decodeItems(from data: Data) throws -> [NasaApodItem] {
        if let array = try? JSONDecoder().decode([NasaApodItem].self, from: data) {
            return array
        }
        
        if let single = try? JSONDecoder().decode(NasaApodItem.self, from: data) {
            return [single]
        }
        
        throw URLError(.cannotDecodeContentData)
    }
}
