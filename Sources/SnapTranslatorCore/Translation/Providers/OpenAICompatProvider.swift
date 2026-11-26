import Foundation

/// OpenAI 兼容接口：支持智谱 GLM / DeepSeek / OpenAI / OpenRouter / Ollama 等任意兼容端点
/// - 支持 SSE 流式增量输出（stream: true），显著降低长文本体感延迟
/// - 支持按编号块翻译协议，确保 1:1 图片覆盖模式块级精准对齐
/// - 支持连接测试与轻量 AI 划词速释
public struct OpenAICompatProvider: TranslationProviding {
    public let name: String
    public let providerID: String
    public var supportsStreaming: Bool { true }

    private let endpoint: URL
    private let model: String
    private let apiKey: String
    private let requiresAPIKey: Bool
    private let session: URLSession

    public init(
        name: String = "AI 模型",
        profileID: String = AIProfile.defaultZhipuID,
        baseURL: String,
        model: String,
        apiKey: String,
        requiresAPIKey: Bool = true,
        session: URLSession = .shared
    ) {
        self.name = name.isEmpty ? "AI 模型" : name
        self.providerID = "openai:\(profileID)"
        self.endpoint = Self.normalizeEndpoint(baseURL)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requiresAPIKey = requiresAPIKey
        self.session = session
    }

    public var isAvailable: Bool {
        guard !model.isEmpty else { return false }
        return !requiresAPIKey || !apiKey.isEmpty
    }

    public static func normalizeEndpoint(_ rawBaseURL: String) -> URL {
        let trimmed = rawBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let normalized = trimmed.hasSuffix("/chat/completions") ? trimmed : trimmed + "/chat/completions"
        return URL(string: normalized) ?? URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
    }

    public func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> String {
        let request = try buildRequest(
            systemPrompt: Self.makeSystemPrompt(source: source, target: target, style: style),
            userContent: text,
            stream: false
        )
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        guard let content = Self.parseCompletionContent(data) else {
            throw TranslationError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func translateStream(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let request = try buildRequest(
            systemPrompt: Self.makeSystemPrompt(source: source, target: target, style: style),
            userContent: text,
            stream: true
        )

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = Data()
            for try await chunk in bytes {
                errorBody.append(chunk)
                if errorBody.count > 4096 { break }
            }
            try validateHTTPResponse(response, data: errorBody)
        }

        // 若后端忽略 stream 参数直接返回完整 JSON，兼容解析
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json") && !contentType.contains("event-stream") {
            var fullData = Data()
            for try await byte in bytes {
                fullData.append(byte)
            }
            guard let content = Self.parseCompletionContent(fullData) else {
                throw TranslationError.emptyResponse
            }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            onPartial(trimmed)
            return trimmed
        }

        var accumulated = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let delta = Self.parseSSEDeltaLine(line) else { continue }
            if delta == Self.sseDoneSentinel { break }
            if !delta.isEmpty {
                accumulated += delta
                onPartial(accumulated)
            }
        }

        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return final
    }

    /// 编号块翻译：供 1:1 图片覆盖模式使用，确保每个视觉块 100% 精准对应
    public func translateBlocks(
        _ blocks: [String],
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> [String]? {
        guard blocks.count > 1 else { return nil }
        let numberedInput = blocks.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: "\n")

        let sourceNote = source.map { "Source language: \($0.promptName). " } ?? ""
        let systemPrompt = """
        You are a professional translator. \(sourceNote)Translate each numbered line into \(target.promptName).
        \(style.promptInstruction)
        CRITICAL FORMAT RULE: Keep the exact same numbering prefix [1], [2], ... [\(blocks.count)] on separate lines. Output ONLY the numbered translations, nothing else.
        """

        let request = try buildRequest(systemPrompt: systemPrompt, userContent: numberedInput, stream: false)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        guard let raw = Self.parseCompletionContent(data) else { return nil }
        return Self.parseNumberedBlocks(raw, expectedCount: blocks.count)
    }

    /// 轻量 AI 划词速释：音标/词性/核心释义/当前语境含义
    public func quickExplain(phrase: String, context: String, target: Language) async throws -> String {
        let systemPrompt = """
        You are a concise bilingual dictionary assistant. Explain the selected word/phrase in \(target.promptName).
        Format cleanly in 3-4 short lines:
        - 词性 & 读音/音标（如适用）
        - 核心释义
        - 语境含义（结合给定上下文，若无上下文则省略）
        Keep it brief, accurate, and easy to scan. No markdown code fences.
        """
        let userContent = context.isEmpty || context == phrase
            ? "词条：\(phrase)"
            : "词条：\(phrase)\n上下文：\(context)"

        let request = try buildRequest(systemPrompt: systemPrompt, userContent: userContent, stream: false)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        guard let content = Self.parseCompletionContent(data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw TranslationError.emptyResponse
        }
        return content
    }

    /// 设置页「测试连接」：发起最小翻译验证 Key / URL / 模型 / 代理
    public func testConnection() async throws -> TimeInterval {
        let start = Date()
        let result = try await translate("Hello", from: .en, to: .zhHans, style: .general)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }
        return Date().timeIntervalSince(start)
    }

    // MARK: - 请求构建与解析（公开静态方法方便单测）

    private static let sseDoneSentinel = "__ST_SSE_DONE__"

    private static func makeSystemPrompt(source: Language?, target: Language, style: TranslationStyle) -> String {
        let sourceNote = source.map { "The source language is \($0.promptName). " } ?? ""
        return "You are a professional translator. \(sourceNote)Translate the user's text into \(target.promptName). \(style.promptInstruction) Output ONLY the translation, nothing else."
    }

    private func buildRequest(systemPrompt: String, userContent: String, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = engineTimeoutSeconds

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return
        }
        if http.statusCode == 429 {
            throw TranslationError.rateLimited(name)
        }
        let detail = Self.parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
        throw TranslationError.httpError(provider: "\(name) (\(model))", statusCode: http.statusCode, detail: detail)
    }

    public static func parseCompletionContent(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        return content
    }

    public static func parseSSEDeltaLine(_ rawLine: String) -> String? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return sseDoneSentinel }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    public static func parseNumberedBlocks(_ raw: String, expectedCount: Int) -> [String]? {
        guard expectedCount > 0 else { return nil }
        let lines = raw.components(separatedBy: .newlines)
        var map: [Int: String] = [:]
        var currentIndex: Int?

        let regex = try? NSRegularExpression(pattern: #"^\s*\[(\d+)\]\s*(.*)$"#)
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex?.firstMatch(in: line, range: range),
               let idx = Int(ns.substring(with: match.range(at: 1))),
               (1...expectedCount).contains(idx) {
                let text = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                map[idx] = text
                currentIndex = idx
            } else if let idx = currentIndex {
                let extra = line.trimmingCharacters(in: .whitespaces)
                if !extra.isEmpty {
                    map[idx] = (map[idx] ?? "") + "\n" + extra
                }
            }
        }

        guard map.count == expectedCount else { return nil }
        return (1...expectedCount).compactMap { map[$0] }
    }

    public static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            return msg
        }
        if let msg = json["message"] as? String { return msg }
        if let detail = json["detail"] as? String { return detail }
        return nil
    }
}
