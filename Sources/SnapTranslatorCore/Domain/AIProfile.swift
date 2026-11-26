import Foundation

/// OpenAI 兼容 AI 引擎预设（支持智谱 GLM / DeepSeek / OpenAI / OpenRouter / Ollama / 自定义）
public struct AIProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var model: String
    /// 对应 Keychain 的账户键；本地服务（如 Ollama）可无需 API Key
    public var requiresAPIKey: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        model: String,
        requiresAPIKey: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.requiresAPIKey = requiresAPIKey
    }

    public var keychainKey: String {
        if id == Self.defaultZhipuID {
            // 复用历史 Keychain 键，老用户升级零迁移成本
            return "st.openai.key"
        }
        return "st.ai.profile.\(id).key"
    }

    public static let defaultZhipuID = "builtin-zhipu-glm"

    public static let builtInTemplates: [AIProfile] = [
        AIProfile(
            id: defaultZhipuID,
            name: "智谱 AI",
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            model: "glm-5.2",
            requiresAPIKey: true
        ),
        AIProfile(
            id: "template-deepseek",
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            requiresAPIKey: true
        ),
        AIProfile(
            id: "template-openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            requiresAPIKey: true
        ),
        AIProfile(
            id: "template-openrouter",
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            model: "google/gemini-2.5-flash",
            requiresAPIKey: true
        ),
        AIProfile(
            id: "template-ollama",
            name: "Ollama (本地)",
            baseURL: "http://127.0.0.1:11434/v1",
            model: "qwen2.5:7b",
            requiresAPIKey: false
        ),
    ]
}
