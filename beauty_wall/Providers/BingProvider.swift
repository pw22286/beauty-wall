import Foundation

struct BingArchiveResponse: Codable {
    let images: [BingArchiveImage]
}

struct BingArchiveImage: Codable {
    let url: String
    let urlbase: String?
    let title: String?
    let copyright: String?
}

public class BingProvider: WallpaperProvider {
    public var providerName: String { "Bing" }
    
    private let config: BingConfig
    
    public init(config: BingConfig) {
        self.config = config
    }
    
    public func fetchRandomWallpaper() async throws -> WallpaperModel {
        var urlComponents = URLComponents(string: "https://cn.bing.com/HPImageArchive.aspx")!
        urlComponents.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: "\(effectiveDayOffset)"),
            URLQueryItem(name: "n", value: "\(effectiveCount)"),
            URLQueryItem(name: "mkt", value: effectiveMarket)
        ]
        
        guard let requestURL = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        print("[beauty_wall][Bing] 请求URL=\(requestURL.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(BingArchiveResponse.self, from: data)
        guard let picked = decoded.images.randomElement(),
              let imageURL = resolveImageURL(from: picked.url) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        let imageId = resolveImageId(from: picked)
        let resolution = resolveResolution(from: imageURL)
        let widthText = resolution.width.map(String.init) ?? "unknown"
        let heightText = resolution.height.map(String.init) ?? "unknown"
        print("[beauty_wall][Bing] 命中图片 id=\(imageId) title=\(picked.title ?? "-") resolution=\(widthText)x\(heightText)")
        
        return WallpaperModel(
            id: imageId,
            url: imageURL,
            sourceName: providerName,
            author: picked.copyright,
            width: resolution.width,
            height: resolution.height
        )
    }
    
    private var effectiveMarket: String {
        let trimmed = config.market.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "zh-CN" : trimmed
    }
    
    private var effectiveDayOffset: Int {
        clampedInt(from: config.dayOffset, defaultValue: 0, range: 0...7)
    }
    
    private var effectiveCount: Int {
        clampedInt(from: config.count, defaultValue: 8, range: 1...8)
    }
    
    private func clampedInt(from raw: String, defaultValue: Int, range: ClosedRange<Int>) -> Int {
        guard let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultValue
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
    
    private func resolveImageURL(from rawURL: String) -> URL? {
        if let absoluteURL = URL(string: rawURL), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: "https://cn.bing.com\(rawURL)")
    }
    
    private func resolveImageId(from image: BingArchiveImage) -> String {
        if let urlbase = image.urlbase,
           let id = extractId(from: "https://cn.bing.com\(urlbase)") {
            return sanitizeId(id)
        }
        
        if let id = extractId(from: image.url) {
            return sanitizeId(id)
        }
        
        return "bing_\(UUID().uuidString)"
    }
    
    private func extractId(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL) else { return nil }
        return components.queryItems?.first(where: { $0.name == "id" })?.value
    }
    
    private func sanitizeId(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }.reduce(into: "") { partialResult, character in
            partialResult.append(character)
        }
    }
    
    private func resolveResolution(from imageURL: URL) -> (width: Int?, height: Int?) {
        guard let components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false) else {
            return (nil, nil)
        }
        
        let width = components.queryItems?.first(where: { $0.name == "w" }).flatMap { Int($0.value ?? "") }
        let height = components.queryItems?.first(where: { $0.name == "h" }).flatMap { Int($0.value ?? "") }
        return (width, height)
    }
}
