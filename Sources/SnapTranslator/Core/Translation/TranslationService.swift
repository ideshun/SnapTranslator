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
        var proxy: EngineProxySettings? = nil
    }

    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// 翻译并返回（译文, 引擎名, 降级说明），全部引擎失败时抛错
    /// 降级说明：主链上有引擎失败、由后续引擎接手时非 nil，供 UI 提示用户
    /// （否则「自动」模式下悄悄落到 Apple 本地，用户会疑惑 Google 怎么不工作了）
    func translate(_ text: String, from source: Language?, to target: Language) async throws
        -> (translation: String, provider: String, fallback: String?)
    {
        var failures: [String] = []
        var failedNames: [String] = []

        // 源语言与目标语言相同：直接返回原文，不做无意义的翻译
        if let source, source == target {
            return (text, "无需翻译", nil)
        }

        for provider in providers {
            guard provider.isAvailable else { continue }
            // 熔断期内的引擎直接跳过，不再白等
            if EngineBreaker.isBlocked(provider.name) {
                failedNames.append(provider.name)
                failures.append("\(provider.name)：近期失败，已熔断跳过")
                continue
            }
            do {
                let result = try await withTimeout(seconds: engineTimeoutSeconds) {
                    try await provider.translate(text, from: source, to: target)
                }
                if !result.isEmpty {
                    let fallback: String? = failedNames.isEmpty
                        ? nil
                        : "\(failedNames.joined(separator: "、"))不可用，已降级到 \(provider.name)"
                    return (result, provider.name, fallback)
                }
                EngineBreaker.recordFailure(provider.name)
                failedNames.append(provider.name)
                failures.append("\(provider.name)：空结果")
            } catch is CancellationError {
                // 请求被取消：是「被新输入取代」而非引擎故障，不计入熔断
                failures.append("\(provider.name)：已取消")
            } catch {
                EngineBreaker.recordFailure(provider.name)
                failedNames.append(provider.name)
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
        let session = EngineProxySettings.makeSession(config.proxy)

        let openai = OpenAICompatProvider(
            baseURL: config.openaiBaseURL,
            model: config.openaiModel,
            apiKey: config.openaiAPIKey,
            session: session
        )
        let deepl = DeepLProvider(apiKey: config.deeplAPIKey, session: session)
        let google = GoogleProvider(session: session)
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
            // 自动：已配置 Key 的云模型优先（isAvailable 要求 Key 非空，未配置自动跳过）
            // → Google（免费）→ Apple 离线 → DeepL
            push(openai)
            push(google)
            push(apple)
            push(deepl)
        case .apple:
            // Apple 离线翻译优先，失败后自动降级到云引擎
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
