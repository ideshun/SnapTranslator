import XCTest
@testable import SnapTranslatorCore

private struct MockProvider: TranslationProviding {
    let name: String
    let providerID: String
    let requiresNetwork: Bool
    let isAvailable: Bool
    let behavior: @Sendable (String) async throws -> String

    func translate(_ text: String, from source: Language?, to target: Language, style: TranslationStyle) async throws -> String {
        try await behavior(text)
    }
}

final class TranslationAndPersistenceTests: XCTestCase {
    func testGoogleParse() {
        let single = #"[[["你好","hello",null,null,10]],null,"en",null,null,null,null,[]]"#
        XCTAssertEqual(GoogleProvider.parse(Data(single.utf8)), "你好")

        let multi = #"[[["你好，","hello, ",null,null,10],["世界","world",null,null,10]],null,"en"]"#
        XCTAssertEqual(GoogleProvider.parse(Data(multi.utf8)), "你好，世界")

        XCTAssertNil(GoogleProvider.parse(Data("{}".utf8)))
    }

    func testOpenAISSEAndNumberedBlocksParsing() {
        let deltaLine = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        XCTAssertEqual(OpenAICompatProvider.parseSSEDeltaLine(deltaLine), "你好")

        let numbered = """
        [1] 标题翻译
        [2] 这是第一段
        换行补充
        [3] 结尾文本
        """
        let parsed = OpenAICompatProvider.parseNumberedBlocks(numbered, expectedCount: 3)
        XCTAssertEqual(parsed, ["标题翻译", "这是第一段\n换行补充", "结尾文本"])
    }

    func testCancellationDoesNotFallbackToNextProvider() async {
        final class Counter: @unchecked Sendable {
            var secondCalled = false
        }
        let counter = Counter()

        let p1 = MockProvider(name: "P1", providerID: "p1", requiresNetwork: true, isAvailable: true) { _ in
            throw CancellationError()
        }
        let p2 = MockProvider(name: "P2", providerID: "p2", requiresNetwork: true, isAvailable: true) { _ in
            counter.secondCalled = true
            return "SHOULD NOT RUN"
        }

        let service = TranslationService(
            config: .init(primary: .auto, useCache: false),
            cache: TranslationCache(capacity: 8),
            breaker: EngineBreaker(cooldown: 60),
            customProviders: [p1, p2]
        )

        do {
            _ = try await service.translate("hello", from: .en, to: .zhHans)
            XCTFail("应抛出 CancellationError")
        } catch is CancellationError {
            XCTAssertFalse(counter.secondCalled, "取消后绝不应降级调用后续引擎")
        } catch {
            XCTFail("抛出了非预期错误: \(error)")
        }
    }

    func testOfflineOnlyModeBlocksAllNetworkProviders() async {
        let cloud = MockProvider(name: "Cloud", providerID: "cloud", requiresNetwork: true, isAvailable: true) { _ in
            return "CLOUD"
        }
        let service = TranslationService(
            config: .init(primary: .auto, offlineOnly: true, useCache: false),
            cache: TranslationCache(capacity: 8),
            breaker: EngineBreaker(cooldown: 60),
            customProviders: [cloud]
        )
        do {
            _ = try await service.translate("hello", from: .en, to: .zhHans)
            XCTFail("纯离线模式不应放行云引擎")
        } catch let err as TranslationError {
            if case .offlineModeUnavailable = err {
                // OK
            } else {
                XCTFail("应返回 offlineModeUnavailable，实际为 \(err)")
            }
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testFineGrainedEngineBreakerScopesLanguagePair() {
        let breaker = EngineBreaker(cooldown: 60)
        breaker.recordFailure("apple", source: .ru, target: .zhHans, languagePairScoped: true)

        XCTAssertTrue(breaker.isBlocked("apple", source: .ru, target: .zhHans))
        XCTAssertFalse(breaker.isBlocked("apple", source: .en, target: .zhHans))
    }

    func testTranslationCacheLRU() {
        let cache = TranslationCache(capacity: 2)
        cache.set("k1", translation: "v1", provider: "P")
        cache.set("k2", translation: "v2", provider: "P")
        _ = cache.get("k1") // k1 变新，k2 变旧
        cache.set("k3", translation: "v3", provider: "P")

        XCTAssertNotNil(cache.get("k1"))
        XCTAssertNil(cache.get("k2"))
        XCTAssertNotNil(cache.get("k3"))
    }

    @MainActor
    func testWordBookStoreAndMultiFormatExport() throws {
        let store = WordBookStore(inMemory: true)
        XCTAssertTrue(store.add(phrase: "ephemeral", context: "ephemeral session", translation: "短暂的", source: "en", target: "zh-Hans"))
        XCTAssertEqual(store.words.count, 1)
        XCTAssertEqual(store.words.first?.translation, "短暂的")

        let id = try XCTUnwrap(store.words.first?.id)
        XCTAssertTrue(store.update(wordID: id, note: "高频技术词", tags: ["技术", "网络"]))
        XCTAssertEqual(store.words.first?.note, "高频技术词")
        XCTAssertEqual(store.words.first?.tags, ["技术", "网络"])

        let csv = WordBookExporter.csv(for: store.words)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("ephemeral"))
        XCTAssertTrue(csv.contains("短暂的"))

        let tsv = WordBookExporter.ankiTSV(for: store.words)
        XCTAssertTrue(tsv.contains("ephemeral\t"))
        XCTAssertTrue(tsv.contains("技术 网络"))

        let json = try WordBookExporter.jsonData(for: store.words)
        let store2 = WordBookStore(inMemory: true)
        let imported = try store2.importJSON(json)
        XCTAssertEqual(imported, 1)
        XCTAssertEqual(store2.words.first?.phrase, "ephemeral")
    }

    @MainActor
    func testHistoryStorePersistenceAndStarPreservation() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("st-hist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = HistoryStore(customDirectory: tempDir)
        let r1 = store.append(image: nil, sourceText: "first", translatedText: "第一", sourceLanguage: .en, targetLanguage: .zhHans, providerName: "Test", ocrLines: [], limit: 2)
        if let id = r1?.id { store.toggleStar(id) }
        _ = store.append(image: nil, sourceText: "second", translatedText: "第二", sourceLanguage: .en, targetLanguage: .zhHans, providerName: "Test", ocrLines: [], limit: 2)
        _ = store.append(image: nil, sourceText: "third", translatedText: "第三", sourceLanguage: .en, targetLanguage: .zhHans, providerName: "Test", ocrLines: [], limit: 2)
        _ = store.append(image: nil, sourceText: "fourth", translatedText: "第四", sourceLanguage: .en, targetLanguage: .zhHans, providerName: "Test", ocrLines: [], limit: 2)

        // limit = 2 保留 2 条非星标 + 1 条星标 = 3 条
        XCTAssertEqual(store.records.count, 3)
        XCTAssertTrue(store.records.contains(where: { $0.sourceText == "first" && $0.isStarred }))

        // 重新从磁盘加载验证持久化
        let reloaded = HistoryStore(customDirectory: tempDir)
        XCTAssertEqual(reloaded.records.count, 3)
        XCTAssertTrue(reloaded.records.contains(where: { $0.sourceText == "first" && $0.isStarred }))
    }

    @MainActor
    func testHistoryStoreUnlimitedRetention() {
        let store = HistoryStore(inMemory: true)
        for i in 1...15 {
            _ = store.append(
                image: nil,
                sourceText: "item \(i)",
                translatedText: "条目 \(i)",
                sourceLanguage: .en,
                targetLanguage: .zhHans,
                providerName: "Test",
                ocrLines: [],
                limit: HistoryStore.unlimitedLimit
            )
        }
        XCTAssertEqual(store.records.count, 15)
        store.trim(limit: HistoryStore.unlimitedLimit)
        XCTAssertEqual(store.records.count, 15)

        // limit = 0 时不新增
        let skipped = store.append(
            image: nil,
            sourceText: "ignored",
            translatedText: "忽略",
            sourceLanguage: .en,
            targetLanguage: .zhHans,
            providerName: "Test",
            ocrLines: [],
            limit: 0
        )
        XCTAssertNil(skipped)
    }
}
