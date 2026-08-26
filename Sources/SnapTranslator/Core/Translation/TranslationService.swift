import Foundation

/// 翻译调度：按设置组装引擎顺序，失败自动降级，单引擎限时
@MainActor
struct TranslationService {
    struct Config {
        var primary: PrimaryEngine
        var openaiBaseURL: String
        var openaiModel: String
        var openaiAPIKey: String
        var deeplAPIKey: String
        var anchor: TranslationAnchor?
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// 翻译并返回（译文, 引擎名），全部引擎失败时抛错
    func translate(_ text: String, from source: Language?, to target: Language) async throws -> (String, String) {
        var failures: [String] = []

        // 源语言与目标语言相同：直接返回原文，不做无意义的翻译
        if let source, source == target {
            return (text, "无需翻译")
        }

        // 仅离线模式下 Apple 翻译不可用（系统 < macOS 15）时，直接给出明确错误，绝不联网
        if config.primary == .offline && !supportsOfflineApple {
            throw TranslationError.noOfflineEngine
        }

        for provider in providers {
            guard provider.isAvailable else { continue }
            do {
                let result = try await withTimeout(seconds: engineTimeoutSeconds) {
                    try await provider.translate(text, from: source, to: target)
                }
                if !result.isEmpty {
                    return (result, provider.name)
                }
                failures.append("\(provider.name)：空结果")
            } catch is CancellationError {
                failures.append("\(provider.name)：已取消")
            } catch {
                failures.append("\(provider.name)：\(error.localizedDescription)")
            }
        }
        throw TranslationError.allFailed(failures)
    }

    /// 当前系统是否具备 Apple 离线翻译能力（macOS 15+ 且锚点已挂载）
    private var supportsOfflineApple: Bool {
        if #available(macOS 15.0, *) {
            return config.anchor != nil
        }
        return false
    }

    /// 按主引擎策略排列引擎顺序（主引擎优先，其余作为降级链）
    private var providers: [TranslationProviding] {
        var ordered: [TranslationProviding] = []

        let openai = OpenAICompatProvider(
            baseURL: config.openaiBaseURL,
            model: config.openaiModel,
            apiKey: config.openaiAPIKey
        )
        let deepl = DeepLProvider(apiKey: config.deeplAPIKey)
        let google = GoogleProvider()
        var apple: TranslationProviding?
        if #available(macOS 15.0, *), let anchor = config.anchor {
            apple = AppleTranslationProvider(anchor: anchor)
        }

        func push(_ provider: TranslationProviding?) {
            if let provider, !ordered.contains(where: { $0.name == provider.name }) {
                ordered.append(provider)
            }
        }

        switch config.primary {
        case .offline:
            // 仅离线：只用 Apple 本地翻译，绝不降级到任何网络引擎
            push(apple)
        case .auto:
            // 离线优先：Apple → GLM5.2（OpenAI兼容，若已配置）→ Google → DeepL
            // 智谱 AI 在国内可用，优先于 Google
            push(apple)
            push(openai)
            push(google)
            push(deepl)
        case .apple:
            push(apple)
            push(openai)
            push(google)
            push(deepl)
        case .openai:
            push(openai)
            push(apple)
            push(google)
            push(deepl)
        case .deepl:
            push(deepl)
            push(apple)
            push(openai)
            push(google)
        case .google:
            push(google)
            push(openai)
            push(apple)
            push(deepl)
        }
        return ordered
    }
}

/// 竞速超时：操作与计时器先完成者胜
private func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TranslationError.timeout
        }
        guard let result = try await group.next() else {
            throw TranslationError.timeout
        }
        group.cancelAll()
        return result
    }
}
