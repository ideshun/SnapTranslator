import Foundation

/// Google 免费翻译接口（零配置兜底，增加 HTTP 状态码校验与 429 限流识别）
public struct GoogleProvider: TranslationProviding {
    public let name = "Google"
    public let providerID = "google"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var isAvailable: Bool { true }

    public func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source?.googleCode ?? "auto"),
            URLQueryItem(name: "tl", value: target.googleCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = engineTimeoutSeconds
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 429 {
                throw TranslationError.rateLimited(name)
            }
            throw TranslationError.httpError(provider: name, statusCode: http.statusCode, detail: "HTTP \(http.statusCode)")
        }
        guard let result = Self.parse(data), !result.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return result
    }

    /// 解析嵌套数组响应：[[["译文","原文",null,null,10],...],...]
    public static func parse(_ data: Data) -> String? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = top.first as? [Any]
        else { return nil }
        var result = ""
        for segment in segments {
            if let array = segment as? [Any],
               let translated = array.first as? String {
                result += translated
            }
        }
        return result
    }
}
