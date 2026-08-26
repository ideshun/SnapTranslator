import Foundation

/// OpenAI 兼容接口：可指向 OpenAI / 智谱 AI / new-api / OpenRouter 等任意兼容端点
struct OpenAICompatProvider: TranslationProviding {
    let name = "GLM5.2"

    private let baseURL: URL
    private let model: String
    private let apiKey: String

    init(baseURL: String, model: String, apiKey: String) {
        // 归一化：去尾部斜杠后拼接 chat/completions
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let normalized = trimmed.hasSuffix("/chat/completions") ? trimmed : trimmed + "/chat/completions"
        self.baseURL = URL(string: normalized) ?? URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        self.model = model
        self.apiKey = apiKey
    }

    var isAvailable: Bool { !apiKey.isEmpty && !model.isEmpty }

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = engineTimeoutSeconds

        let sourceNote = source.map { "The source language is \($0.displayName). " } ?? ""
        let systemPrompt = "You are a professional translator. \(sourceNote)Translate the user's text into \(target.displayName). Output ONLY the translation, nothing else."
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 尝试解析错误响应中的 message 字段
            let errMsg = Self.parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "GLM5.2", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "\(model) 请求失败：\(errMsg)"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw TranslationError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 OpenAI 兼容 API 错误响应中的 message 字段
    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            return msg
        }
        if let msg = json["message"] as? String {
            return msg
        }
        if let detail = json["detail"] as? String {
            return detail
        }
        return nil
    }
}
