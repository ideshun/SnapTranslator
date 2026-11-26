import AppKit
import Foundation
import SnapTranslatorCore

/// 翻译链路诊断模式：`SnapTranslator --translate "文本" [--to zh-Hans] [--from en] [--cycle]`
/// 复用统一 LanguagePolicy 与 TranslationService
@MainActor
enum TranslateDiag {
    static func run(arguments: [String]) -> Int32 {
        guard let textIndex = arguments.firstIndex(of: "--translate"),
              textIndex + 1 < arguments.count else {
            print("用法：SnapTranslator --translate \"要翻译的文本\" [--to <语言代码>] [--from <语言代码>]")
            return 2
        }
        let text = arguments[textIndex + 1]
        var targetOverride: Language?
        if let toIndex = arguments.firstIndex(of: "--to"), toIndex + 1 < arguments.count {
            targetOverride = Language(rawValue: arguments[toIndex + 1])
        }
        var fromOverride: Language?
        if let fromIndex = arguments.firstIndex(of: "--from"), fromIndex + 1 < arguments.count {
            fromOverride = Language(rawValue: arguments[fromIndex + 1])
        }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore()
        let host = TranslationHostWindowController()
        host.show()

        let resolved: ResolvedLanguagePair
        if let forced = fromOverride {
            resolved = ResolvedLanguagePair(source: forced, target: targetOverride ?? settings.targetLanguage)
        } else {
            resolved = LanguagePolicy.resolve(
                text: text,
                sessionSourceOverride: nil,
                persistentSourceLock: settings.persistentSourceLanguage,
                preferredTarget: targetOverride ?? settings.targetLanguage
            )
        }

        print("== 翻译诊断 ==")
        print("主引擎策略：\(settings.primaryEngine.rawValue)（纯离线：\(settings.offlineOnlyMode)）")
        print("AI 预设：\(settings.activeAIProfile.name) / \(settings.activeAIProfile.model)")
        print("语向：\(resolved.source?.rawValue ?? "自动检测") → \(resolved.target.rawValue)")
        print("文本：\(text)")

        let service = TranslationService(
            config: settings.makeTranslationConfig(anchor: host.anchor)
        )

        let semaphore = DispatchSemaphore(value: 0)
        let cycleMode = arguments.contains("--cycle")
        let texts = [text, "第二次请求测试文本。", "Third request text for repeat test."]
        var results: [String] = []
        var failed = false

        for (index, item) in texts.enumerated() {
            if index > 0 && cycleMode {
                host.hide()
                host.show()
                results.append("  （--cycle：已执行 hide → show）")
            }
            Task { @MainActor in
                do {
                    let outcome = try await service.translate(item, from: resolved.source, to: resolved.target)
                    results.append("  #\(index + 1) OK engine=\(outcome.provider) cache=\(outcome.fromCache) → \(outcome.translation)")
                } catch {
                    results.append("  #\(index + 1) FAIL → \(error.localizedDescription)")
                    failed = true
                }
                semaphore.signal()
            }
            let deadline = Date().addingTimeInterval(30)
            var done = false
            while Date() < deadline {
                if semaphore.wait(timeout: .now() + 0.05) == .success { done = true; break }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            if !done {
                results.append("  #\(index + 1) TIMEOUT（30s 无返回）")
                failed = true
                break
            }
        }

        print("== 结果 ==")
        print(results.joined(separator: "\n"))
        host.hide()
        if failed { return results.joined().contains("TIMEOUT") ? 2 : 1 }
        return 0
    }
}
