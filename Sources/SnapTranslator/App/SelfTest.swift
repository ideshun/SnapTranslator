import Carbon.HIToolbox
import Foundation

/// 内建自测：`SnapTranslator --self-test` 运行，退出码为失败数
/// （CLT 工具链缺 XCTest/Testing 运行时，用零依赖方案替代单测框架）
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
        testGoogleParse()
        testWordBook()
        testCSVExport()

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

    // MARK: - HotkeySpec

    private static func testHotkeySpec() {
        check("HotkeySpec 显示 ⌥S",
              HotkeySpec(keyCode: 1, modifiers: UInt32(optionKey)).display == "⌥S")
        check("HotkeySpec 显示 ⌥⇧S",
              HotkeySpec(keyCode: 1, modifiers: UInt32(optionKey | shiftKey)).display == "⌥⇧S")
        check("HotkeySpec 显示 ⌘T",
              HotkeySpec(keyCode: 17, modifiers: UInt32(cmdKey)).display == "⌘T")
        check("修饰键转换 option+shift",
              HotkeySpec.carbon(from: [.option, .shift]) == UInt32(optionKey | shiftKey))
        check("修饰键转换 command+control",
              HotkeySpec.carbon(from: [.command, .control]) == UInt32(cmdKey | controlKey))

        let spec = HotkeySpec(keyCode: 17, modifiers: UInt32(optionKey))
        var roundTrip: HotkeySpec?
        if let data = try? JSONEncoder().encode(spec) {
            roundTrip = try? JSONDecoder().decode(HotkeySpec.self, from: data)
        }
        check("HotkeySpec Codable 往返", roundTrip == spec)
    }

    // MARK: - Language

    private static func testLanguage() {
        check("google 码 zh-Hans", Language.zhHans.googleCode == "zh-CN")
        check("google 码 zh-Hant", Language.zhHant.googleCode == "zh-TW")
        check("google 码 ja", Language.ja.googleCode == "ja")
        check("deepl 码 zh-Hans", Language.zhHans.deeplCode == "ZH")
        check("deepl 码 uk", Language.uk.deeplCode == "UK")
        check("deepl 码 en", Language.en.deeplCode == "EN")
    }

    private static func testLanguageDetector() {
        check("语种检测 英文",
              LanguageDetector.detect("The quick brown fox jumps over the lazy dog near the river.") == .en)
        check("语种检测 中文",
              LanguageDetector.detect("今天天气不错，一起出去走走，顺便吃个午饭。") == .zhHans)
        check("语种检测 日文",
              LanguageDetector.detect("こちらの商品はとても人気があります。") == .ja)
        check("语种检测 空文本", LanguageDetector.detect("") == nil)
    }

    // MARK: - Google 解析

    private static func testGoogleParse() {
        let single = #"[[["你好","hello",null,null,10]],null,"en",null,null,null,null,[]]"#
        check("Google 解析 单段", GoogleProvider.parse(Data(single.utf8)) == "你好")
        let multi = #"[[["你好，","hello, ",null,null,10],["世界","world",null,null,10]],null,"en"]"#
        check("Google 解析 多段", GoogleProvider.parse(Data(multi.utf8)) == "你好，世界")
        check("Google 解析 非法输入", GoogleProvider.parse(Data("{}".utf8)) == nil)
    }

    // MARK: - 生词本

    private static func testWordBook() {
        let store = WordBookStore(inMemory: true)
        check("生词 收藏", store.add(phrase: "hello", context: "hello world", source: "en", target: "zh-Hans"))
        check("生词 数量为 1", store.words.count == 1)
        check("生词 重复收藏去重",
              store.add(phrase: "hello", context: "say hello to me", source: "en", target: "zh-Hans"))
        check("生词 去重后仍为 1 条", store.words.count == 1)
        check("生词 上下文已更新", store.words.first?.context == "say hello to me")
        if let word = store.words.first {
            store.delete(word)
        }
        check("生词 删除", store.words.isEmpty)
    }

    private static func testCSVExport() {
        check("CSV 转义 普通字段", WordBookExporter.escape("plain") == "plain")
        check("CSV 转义 逗号", WordBookExporter.escape("a,b") == "\"a,b\"")
        check("CSV 转义 引号", WordBookExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")

        let store = WordBookStore(inMemory: true)
        store.add(phrase: "test", context: "this is a test", source: "en", target: "zh-Hans")
        let csv = WordBookExporter.csv(for: store.words)
        check("CSV 含 BOM", csv.hasPrefix("\u{FEFF}"))
        check("CSV 含表头", csv.contains("词,上下文,源语言,目标语言,收藏时间"))
        check("CSV 含词条", csv.contains("test"))
    }
}
