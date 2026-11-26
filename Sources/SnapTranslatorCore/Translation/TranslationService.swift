import Foundation

/// 翻译调度中枢：
/// - 严格执行纯离线隐私模式（offlineOnly 时绝不调用或降级到云引擎）
/// - 正确传播 CancellationError（取消时不误降级到下一引擎）
/// - 集成 LRU 缓存、细粒度熔断器、URLSession 池与流式增量回调
/// - 支持 1:1 编号块翻译与双引擎并排对比
public struct TranslationService: Sendable {
    public struct Config: Sendable {
        public var primary: PrimaryEngine
        public var aiProfile: AIProfile
        public var aiAPIKey: String
        public var deeplAPIKey: String
        public var anchor: TranslationAnchor?
        public var proxy: EngineProxySettings?
        public var offlineOnly: Bool
        public var style: TranslationStyle
        public var useCache: Bool

        public init(
            primary: PrimaryEngine,
            aiProfile: AIProfile = AIProfile.builtInTemplates[0],
            aiAPIKey: String = "",
            deeplAPIKey: String = "",
            anchor: TranslationAnchor? = nil,
            proxy: EngineProxySettings? = nil,
            offlineOnly: Bool = false,
            style: TranslationStyle = .general,
            useCache: Bool = true
        ) {
            self.primary = primary
            self.aiProfile = aiProfile
            self.aiAPIKey = aiAPIKey
            self.deeplAPIKey = deeplAPIKey
            self.anchor = anchor
            self.proxy = proxy
            self.offlineOnly = offlineOnly
            self.style = style
            self.useCache = useCache
        }
    }

    private let config: Config
    private let cache: TranslationCache
    private let breaker: EngineBreaker
    private let sessionPool: NetworkSessionPool
    private let customProviders: [TranslationProviding]?

    public init(
        config: Config,
        cache: TranslationCache = .shared,
        breaker: EngineBreaker = .shared,
        sessionPool: NetworkSessionPool = .shared,
        customProviders: [TranslationProviding]? = nil
    ) {
        self.config = config
        self.cache = cache
        self.breaker = breaker
        self.sessionPool = sessionPool
        self.customProviders = customProviders
    }

    /// 执行翻译（支持可选流式增量回调）
    public func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> TranslationOutcome {
        if let source, source == target {
            return TranslationOutcome(translation: text, provider: "无需翻译", fallbackNotice: nil, fromCache: false)
        }

        let cacheKey = TranslationCache.makeKey(
            engine: config.primary,
            profileID: config.aiProfile.id,
            source: source,
            target: target,
            style: config.style,
            offlineOnly: config.offlineOnly,
            text: text
        )
        if config.useCache, let cached = cache.get(cacheKey) {
            onPartial?(cached.translation)
            return TranslationOutcome(
                translation: cached.translation,
                provider: cached.provider,
                fallbackNotice: nil,
                fromCache: true
            )
        }

        let candidates = buildProviders()
        if config.offlineOnly && candidates.isEmpty {
            throw TranslationError.offlineModeUnavailable
        }

        var failures: [String] = []
        var failedNames: [String] = []

        for provider in candidates {
            try Task.checkCancellation()
            guard provider.isAvailable else { continue }

            if breaker.isBlocked(provider.providerID, source: source, target: target) {
                failedNames.append(provider.name)
                failures.append("\(provider.name)：近期失败，已熔断跳过")
                continue
            }

            do {
                let result: String
                if let onPartial, provider.supportsStreaming {
                    result = try await withTimeout(seconds: engineTimeoutSeconds) {
                        try await provider.translateStream(
                            text,
                            from: source,
                            to: target,
                            style: config.style,
                            onPartial: onPartial
                        )
                    }
                } else {
                    result = try await withTimeout(seconds: engineTimeoutSeconds) {
                        try await provider.translate(text, from: source, to: target, style: config.style)
                    }
                }

                if !result.isEmpty {
                    breaker.recordSuccess(provider.providerID, source: source, target: target)
                    if config.useCache {
                        cache.set(cacheKey, translation: result, provider: provider.name)
                    }
                    let fallback: String? = failedNames.isEmpty
                        ? nil
                        : "\(failedNames.joined(separator: "、"))不可用，已降级到 \(provider.name)"
                    return TranslationOutcome(
                        translation: result,
                        provider: provider.name,
                        fallbackNotice: fallback,
                        fromCache: false
                    )
                }

                breaker.recordFailure(provider.providerID, source: source, target: target, languagePairScoped: false)
                failedNames.append(provider.name)
                failures.append("\(provider.name)：空结果")
            } catch is CancellationError {
                // 关键修复：取消必须立即向上抛出，绝不降级调用下一个引擎
                throw CancellationError()
            } catch {
                let pairScoped = Self.isLanguagePairScopedError(error)
                breaker.recordFailure(provider.providerID, source: source, target: target, languagePairScoped: pairScoped)
                failedNames.append(provider.name)
                failures.append("\(provider.name)：\(error.localizedDescription)")
            }
        }

        if config.offlineOnly {
            if failures.isEmpty {
                throw TranslationError.offlineModeUnavailable
            }
            throw TranslationError.allFailed(failures)
        }
        throw TranslationError.allFailed(failures)
    }

    /// 1:1 覆盖模式块级精准翻译（优先用可用 AI 引擎编号块协议，确保每块一一对应）
    public func translateBlocks(
        _ blocks: [String],
        from source: Language?,
        to target: Language
    ) async -> [String]? {
        guard !config.offlineOnly, blocks.count > 1 else { return nil }
        let ai = makeOpenAIProvider()
        guard ai.isAvailable else { return nil }
        do {
            return try await withTimeout(seconds: engineTimeoutSeconds) {
                try await ai.translateBlocks(blocks, from: source, to: target, style: config.style)
            }
        } catch {
            AppLogger.translation.debug("块级翻译回退为常规排版: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 轻量 AI 划词速释
    public func quickExplain(phrase: String, context: String, target: Language) async throws -> String {
        guard !config.offlineOnly else {
            throw TranslationError.offlineModeUnavailable
        }
        let ai = makeOpenAIProvider()
        guard ai.isAvailable else {
            throw TranslationError.allFailed(["未配置 AI 模型 API Key，无法使用 AI 速释"])
        }
        return try await withTimeout(seconds: engineTimeoutSeconds) {
            try await ai.quickExplain(phrase: phrase, context: context, target: target)
        }
    }

    /// 使用指定单个引擎进行副引擎对比翻译（不走完整降级链，清晰展示指定引擎输出）
    public func translateWithSpecificEngine(
        _ engine: PrimaryEngine,
        text: String,
        from source: Language?,
        to target: Language
    ) async throws -> TranslationOutcome {
        if config.offlineOnly && engine != .apple {
            throw TranslationError.offlineModeUnavailable
        }
        var subConfig = config
        subConfig.primary = engine
        let subService = TranslationService(
            config: subConfig,
            cache: cache,
            breaker: breaker,
            sessionPool: sessionPool
        )
        return try await subService.translate(text, from: source, to: target)
    }

    // MARK: - 引擎链装配

    private func makeOpenAIProvider() -> OpenAICompatProvider {
        let session = sessionPool.session(for: config.proxy)
        return OpenAICompatProvider(
            name: config.aiProfile.name,
            profileID: config.aiProfile.id,
            baseURL: config.aiProfile.baseURL,
            model: config.aiProfile.model,
            apiKey: config.aiAPIKey,
            requiresAPIKey: config.aiProfile.requiresAPIKey,
            session: session
        )
    }

    private func buildProviders() -> [TranslationProviding] {
        if let customProviders {
            return config.offlineOnly ? customProviders.filter { !$0.requiresNetwork } : customProviders
        }

        let session = sessionPool.session(for: config.proxy)
        var apple: TranslationProviding?
        if #available(macOS 15.0, *), let anchor = config.anchor {
            apple = AppleTranslationProvider(anchor: anchor)
        }

        // 纯离线隐私模式：仅放行 Apple 本地离线引擎，绝不构造任何网络引擎
        if config.offlineOnly {
            return apple.map { [$0] } ?? []
        }

        let openai = makeOpenAIProvider()
        let deepl = DeepLProvider(apiKey: config.deeplAPIKey, session: session)
        let google = GoogleProvider(session: session)

        var ordered: [TranslationProviding] = []
        func push(_ provider: TranslationProviding?) {
            if let provider, !ordered.contains(where: { $0.providerID == provider.providerID }) {
                ordered.append(provider)
            }
        }

        switch config.primary {
        case .auto:
            push(openai)
            push(google)
            push(apple)
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

    private static func isLanguagePairScopedError(_ error: Error) -> Bool {
        if let translationError = error as? TranslationError {
            return translationError.isLanguagePairScoped
        }
        let lower = (String(describing: error) + " " + error.localizedDescription).lowercased()
        return lower.contains("语向") || lower.contains("语言包") || lower.contains("unable to translate")
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
