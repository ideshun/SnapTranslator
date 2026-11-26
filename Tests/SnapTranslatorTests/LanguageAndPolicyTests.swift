import Carbon.HIToolbox
import XCTest
@testable import SnapTranslatorCore

final class LanguageAndPolicyTests: XCTestCase {
    func testHotkeySpecDisplayAndTokens() {
        let s1 = HotkeySpec(keyCode: 1, modifiers: UInt32(optionKey))
        XCTAssertEqual(s1.display, "⌥S")
        XCTAssertEqual(s1.keyTokens, ["⌥", "S"])

        let s2 = HotkeySpec(keyCode: 111, modifiers: UInt32(optionKey | shiftKey))
        XCTAssertEqual(s2.display, "⌥⇧F12")
        // 关键：F12 不应被拆成 "F", "1", "2"
        XCTAssertEqual(s2.keyTokens, ["⌥", "⇧", "F12"])

        let s3 = HotkeySpec(keyCode: 49, modifiers: UInt32(cmdKey))
        XCTAssertEqual(s3.keyTokens, ["⌘", "空格"])

        XCTAssertEqual(HotkeySpec.carbon(from: [.option, .shift]), UInt32(optionKey | shiftKey))
        XCTAssertEqual(HotkeySpec.carbon(from: [.command, .control]), UInt32(cmdKey | controlKey))
    }

    func testLanguageCodes() {
        XCTAssertEqual(Language.zhHans.googleCode, "zh-CN")
        XCTAssertEqual(Language.zhHant.googleCode, "zh-TW")
        XCTAssertEqual(Language.zhHans.deeplSourceCode, "ZH")
        XCTAssertEqual(Language.zhHans.deeplTargetCode, "ZH-HANS")
        XCTAssertEqual(Language.zhHant.deeplTargetCode, "ZH-HANT")
        XCTAssertEqual(Language.en.deeplTargetCode, "EN-US")
        XCTAssertEqual(Language.uk.deeplTargetCode, "UK")
    }

    func testLanguageDetector() {
        XCTAssertEqual(LanguageDetector.detect("The quick brown fox jumps over the lazy dog."), .en)
        XCTAssertEqual(LanguageDetector.detect("今天天气不错，一起出去走走。"), .zhHans)
        XCTAssertEqual(LanguageDetector.detect("繁體中文測試，一起散步看看風景。"), .zhHant)
        XCTAssertEqual(LanguageDetector.detect("こちらの商品はとても人気があります。"), .ja)
        XCTAssertEqual(LanguageDetector.detect("안녕하세요 반갑습니다"), .ko)
        XCTAssertNil(LanguageDetector.detect(""))
        XCTAssertEqual(LanguageDetector.detect("i"), .en)
        XCTAssertEqual(LanguageDetector.detect("do"), .en)
        XCTAssertEqual(LanguageDetector.detect("“old”"), .en)
        XCTAssertEqual(LanguageDetector.detect("ok"), .en)
    }

    func testLanguagePolicyAutoFlipAndLocks() {
        // 自动检测中文 + 偏好中文 -> 自动反转目标为英文
        let r1 = LanguagePolicy.resolve(
            text: "这是一段中文测试文本",
            sessionSourceOverride: nil,
            persistentSourceLock: nil,
            preferredTarget: .zhHans
        )
        XCTAssertEqual(r1.source, .zhHans)
        XCTAssertEqual(r1.target, .en)
        XCTAssertTrue(r1.wasAutoFlipped)

        // 自动检测繁体中文 + 偏好简体中文 -> 自动反转目标为英文（避开 Apple 简繁报错）
        let r2 = LanguagePolicy.resolve(
            text: "繁體中文測試內容",
            sessionSourceOverride: nil,
            persistentSourceLock: nil,
            preferredTarget: .zhHans
        )
        XCTAssertEqual(r2.source, .zhHant)
        XCTAssertEqual(r2.target, .en)
        XCTAssertTrue(r2.wasAutoFlipped)

        // 自动检测英文 + 偏好英文 -> 自愈切回简体中文
        let r3 = LanguagePolicy.resolve(
            text: "Hello world from Swift",
            sessionSourceOverride: nil,
            persistentSourceLock: nil,
            preferredTarget: .en
        )
        XCTAssertEqual(r3.source, .en)
        XCTAssertEqual(r3.target, .zhHans)
        XCTAssertTrue(r3.wasAutoFlipped)

        // 显式会话锁定具有最高优先级，绝不擅自反转目标
        let r4 = LanguagePolicy.resolve(
            text: "这是一段中文",
            sessionSourceOverride: .en,
            persistentSourceLock: .ja,
            preferredTarget: .zhHans
        )
        XCTAssertEqual(r4.source, .en)
        XCTAssertEqual(r4.target, .zhHans)
        XCTAssertFalse(r4.wasAutoFlipped)
    }
}
