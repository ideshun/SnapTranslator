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
        case .auto:
            // 离线优先：Apple → Google（免费无配置）→ OpenAI → DeepL
            push(apple)
            push(google)
            push(openai)
            push(deepl)
        case .apple:
            push(apple)
            push(google)
            push(openai)
            push(deepl)
        case .openai:
            push(openai)
            push(apple)
            push(google)
            push(deepl)
        case .deepl:
            push(deepl)
            push(apple)
            push(google)
            push(openai)
        case .google:
            push(google)
            push(apple)
            push(openai)
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
