import Foundation

/// DeepL API v2（使用官方推荐的 Authorization Header + JSON 请求体，区分 ZH-HANS/ZH-HANT）
public struct DeepLProvider: TranslationProviding {
    public let name = "DeepL"
    public let providerID = "deepl"

    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        let host = self.apiKey.lowercased().hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        self.endpoint = URL(string: "https://\(host)/v2/translate")!
    }

    public var isAvailable: Bool { !apiKey.isEmpty }

    public func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = engineTimeoutSeconds

        var payload: [String: Any] = [
            "text": [text],
            "target_lang": target.deeplTargetCode,
        ]
        if let source {
            payload["source_lang"] = source.deeplSourceCode
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 429 || http.statusCode == 456 {
                throw TranslationError.rateLimited(name)
            }
            let detail = Self.parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw TranslationError.httpError(provider: name, statusCode: http.statusCode, detail: detail)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String,
              !translated.isEmpty
        else {
            throw TranslationError.emptyResponse
        }
        return translated
    }

    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["message"] as? String
    }
}
