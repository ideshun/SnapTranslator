import Carbon.HIToolbox
import Foundation
import SnapTranslatorCore

/// CLI 内建自测：`SnapTranslator --self-test`，退出码为失败数
@MainActor
enum SelfTest {
    private static var failures = 0
    private static var passed = 0

    static func run() -> Int32 {
        failures = 0
        passed = 0
        print("== SnapTranslator 自测开始 ==")

        testHotkeySpec()
        testLanguage()
        testLanguageDetector()
        testLanguagePolicy()
        testOCRLayout()
        testGoogleParse()
        testOpenAIParsing()
        testWordBook()
        testCSVAndAnkiExport()

        print("== 自测结束：\(passed) 通过 / \(failures) 失败 ==")
        return Int32(failures)
    }

    private static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failures += 1
            print("  ✗ \(name)")
        }
    }

    private static func testHotkeySpec() {
        check("HotkeySpec 显示 ⌥S",
              HotkeySpec(keyCode: 1, modifiers: UInt32(optionKey)).display == "⌥S")
        check("HotkeySpec 显示 ⌥⇧S",
              HotkeySpec(keyCode: 1, modifiers: UInt32(optionKey | shiftKey)).display == "⌥⇧S")
        check("HotkeySpec keyTokens 不拆 F12",
              HotkeySpec(keyCode: 111, modifiers: UInt32(optionKey)).keyTokens == ["⌥", "F12"])
        check("修饰键转换 option+shift",
              HotkeySpec.carbon(from: [.option, .shift]) == UInt32(optionKey | shiftKey))
        let spec = HotkeySpec(keyCode: 17, modifiers: UInt32(optionKey))
        let roundTrip = (try? JSONEncoder().encode(spec)).flatMap { try? JSONDecoder().decode(HotkeySpec.self, from: $0) }
        check("HotkeySpec Codable 往返", roundTrip == spec)
    }

    private static func testLanguage() {
        check("google 码 zh-Hans", Language.zhHans.googleCode == "zh-CN")
        check("google 码 zh-Hant", Language.zhHant.googleCode == "zh-TW")
        check("deepl 目标码 zh-Hans", Language.zhHans.deeplTargetCode == "ZH-HANS")
        check("deepl 目标码 zh-Hant", Language.zhHant.deeplTargetCode == "ZH-HANT")
        check("deepl 源码 zh-Hans", Language.zhHans.deeplSourceCode == "ZH")
    }

    private static func testLanguageDetector() {
        check("语种检测 英文",
              LanguageDetector.detect("The quick brown fox jumps over the lazy dog.") == .en)
        check("语种检测 中文",
              LanguageDetector.detect("今天天气不错，一起出去走走。") == .zhHans)
        check("语种检测 繁体中文",
              LanguageDetector.detect("繁體中文測試，一起散步看看風景。") == .zhHant)
        check("语种检测 日文",
              LanguageDetector.detect("こちらの商品はとても人気があります。") == .ja)
        check("语种检测 短词 ok", LanguageDetector.detect("ok") == .en)
        check("语种检测 空文本", LanguageDetector.detect("") == nil)
    }

    private static func testLanguagePolicy() {
        let r1 = LanguagePolicy.resolve(text: "你好世界", sessionSourceOverride: nil, persistentSourceLock: nil, preferredTarget: .zhHans)
        check("语向自愈 中文→英文", r1.source == .zhHans && r1.target == .en)
        let r2 = LanguagePolicy.resolve(text: "你好世界", sessionSourceOverride: .en, persistentSourceLock: nil, preferredTarget: .zhHans)
        check("语向锁定优先级", r2.source == .en && r2.target == .zhHans)
    }

    private static func testOCRLayout() {
        let lines = [
            OCRLine(text: "auto-", boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.05)),
            OCRLine(text: "mated", boundingBox: CGRect(x: 0.1, y: 0.64, width: 0.4, height: 0.05)),
        ]
        let blocks = OCRLayoutAnalyzer.analyze(lines)
        check("OCR 连字符合并", blocks.count == 1 && blocks[0].mergedText == "automated")
    }

    private static func testGoogleParse() {
        let single = #"[[["你好","hello",null,null,10]],null,"en"]"#
        check("Google 解析 单段", GoogleProvider.parse(Data(single.utf8)) == "你好")
        let multi = #"[[["你好，","hello, "],["世界","world"]],null,"en"]"#
        check("Google 解析 多段", GoogleProvider.parse(Data(multi.utf8)) == "你好，世界")
        check("Google 解析 非法输入", GoogleProvider.parse(Data("{}".utf8)) == nil)
    }

    private static func testOpenAIParsing() {
        let line = #"data: {"choices":[{"delta":{"content":"世界"}}]}"#
        check("OpenAI SSE 增量解析", OpenAICompatProvider.parseSSEDeltaLine(line) == "世界")
        let blocks = OpenAICompatProvider.parseNumberedBlocks("[1] 一\n[2] 二", expectedCount: 2)
        check("OpenAI 编号块解析", blocks == ["一", "二"])
    }

    private static func testWordBook() {
        let store = WordBookStore(inMemory: true)
        check("生词 收藏", store.add(phrase: "hello", context: "hello world", translation: "你好", source: "en", target: "zh-Hans"))
        check("生词 译文保存", store.words.first?.translation == "你好")
        check("生词 重复收藏去重", store.add(phrase: "hello", context: "say hello", source: "en", target: "zh-Hans"))
        check("生词 去重后保留原译文", store.words.count == 1 && store.words.first?.translation == "你好")
        if let w = store.words.first { store.delete(w) }
        check("生词 删除", store.words.isEmpty)
    }

    private static func testCSVAndAnkiExport() {
        check("CSV 转义 逗号", WordBookExporter.escape("a,b") == "\"a,b\"")
        check("CSV 转义 引号", WordBookExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        let store = WordBookStore(inMemory: true)
        store.add(phrase: "test", context: "this is a test", translation: "测试", source: "en", target: "zh-Hans")
        let csv = WordBookExporter.csv(for: store.words)
        check("CSV 含 BOM 与译文", csv.hasPrefix("\u{FEFF}") && csv.contains("测试"))
        let anki = WordBookExporter.ankiTSV(for: store.words)
        check("Anki TSV 导出", anki.contains("test\t测试"))
    }
}
