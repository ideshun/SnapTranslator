import Foundation

/// Google 免费翻译接口（非官方，零配置，作为离线引擎的兜底）
struct GoogleProvider: TranslationProviding {
    let name = "Google"
    /// 网络会话（可携带代理配置）
    var session: URLSession = .shared

    var isAvailable: Bool { true }

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
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
        let (data, _) = try await session.data(from: url)
        guard let result = Self.parse(data), !result.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return result
    }

    /// 解析嵌套数组响应：[[["译文","原文",null,null,10],...],...]
    static func parse(_ data: Data) -> String? {
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
