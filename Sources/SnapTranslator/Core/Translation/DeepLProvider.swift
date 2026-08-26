import Foundation

/// DeepL API（Free 档），需要 API Key
struct DeepLProvider: TranslationProviding {
    let name = "DeepL"

    private let apiKey: String
    /// Free Key 走 api-free 域名，Pro Key 走 api.deepl.com
    private let endpoint: URL

    init(apiKey: String) {
        self.apiKey = apiKey
        let host = apiKey.lowercased().hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        self.endpoint = URL(string: "https://\(host)/v2/translate")!
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents: [URLQueryItem] = [
            URLQueryItem(name: "auth_key", value: apiKey),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: target.deeplCode),
        ]
        if let source {
            bodyComponents.append(URLQueryItem(name: "source_lang", value: source.deeplCode))
        }
        let body = bodyComponents
            .map { component -> String in
                let value = component.value?
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return "\(component.name)=\(value)"
            }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.allFailed(["DeepL HTTP \(http.statusCode)"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String
        else {
            throw TranslationError.emptyResponse
        }
        return translated
    }
}
