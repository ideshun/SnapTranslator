import AppKit
import Foundation

/// 诊断模式：`SnapTranslator --translate "文本"`（可跟 `--to zh-Hans` 指定目标语言）
/// 复用与结果面板完全一致的 TranslationService 链路（含 Apple 翻译锚点窗口），
/// 逐引擎输出成功/失败原因，用于在无 UI 操作的情况下定位「翻译失败」问题。
/// 退出码：0 = 成功，1 = 全部引擎失败，2 = 超时无响应。
@MainActor
enum TranslateDiag {
    static func run(arguments: [String]) -> Int32 {
        guard let textIndex = arguments.firstIndex(of: "--translate"),
              textIndex + 1 < arguments.count else {
            print("用法：SnapTranslator --translate \"要翻译的文本\" [--to <语言代码>]")
            return 2
        }
        let text = arguments[textIndex + 1]
        var targetOverride: Language?
        if let toIndex = arguments.firstIndex(of: "--to"), toIndex + 1 < arguments.count {
            targetOverride = Language(rawValue: arguments[toIndex + 1])
        }
        // --from 强制指定源语言（跳过 hint/检测），用于验证特定语言对是否被 Apple 引擎支持
        var fromOverride: Language?
        if let fromIndex = arguments.firstIndex(of: "--from"), fromIndex + 1 < arguments.count {
            fromOverride = Language(rawValue: arguments[fromIndex + 1])
        }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore()
        let host = TranslationHostWindowController()
        host.show()

        // 镜像应用真实语向逻辑（AppDelegate.determineSourceLanguage / effectiveTargetLanguage）：
        // sourceHint 优先，但 hint==目标 的退化配置下自动检测优先；源==目标时目标自动切英文。
        // --from 则完全绕过语向判定，直接测指定语言对。
        let baseTarget = targetOverride ?? settings.targetLanguage
        let rawSource: Language?
        if let forced = fromOverride {
            rawSource = forced
        } else if let hint = settings.sourceHint {
            rawSource = (hint == baseTarget ? LanguageDetector.detect(text) ?? hint : hint)
        } else {
            rawSource = LanguageDetector.detect(text)
        }
        let source: Language? = rawSource
        // 镜像 AppDelegate.effectiveTargetLanguage：源==目标，或同为中文简繁变体
        // （Apple 不支持 zh-Hant↔zh-Hans 互译），目标自动切英文
        let target: Language
        if fromOverride != nil {
            target = baseTarget
        } else if let src = rawSource {
            let zhVariants: Set<Language> = [.zhHans, .zhHant]
            target = (src == baseTarget || (zhVariants.contains(src) && zhVariants.contains(baseTarget)))
                ? .en : baseTarget
        } else {
            target = baseTarget
        }

        print("== 翻译诊断 ==")
        print("主引擎策略：\(settings.primaryEngine)")
        print("语向：\(source?.rawValue ?? "自动检测") → \(target.rawValue)（settings: \(settings.sourceHint?.rawValue ?? "auto") → \(settings.targetLanguage.rawValue)）")
        print("文本：\(text)")

        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: host.anchor,
                proxy: settings.engineProxy
            )
        )

        let semaphore = DispatchSemaphore(value: 0)
        var outcome = ""

        // --cycle：模拟实时翻译的真实节奏（每次请求完成后 hide 锚点窗口，下次请求前再 show）。
        // diag 常驻窗口时 3/3 通过但实时翻译失败 ⇒ hide/show 循环破坏了后续 translationTask 触发。
        let cycleMode = arguments.contains("--cycle")

        // 同一进程内连续 3 次翻译（同语向、不同文本）：
        // 第 1 次成功而后续挂起 = translationTask 未重复触发类 bug 的决定性证据
        let texts = [text, "第二次请求测试文本。", "Third request text for repeat test."]
        var results: [String] = []
        var failed = false

        for (index, item) in texts.enumerated() {
            if index > 0 && cycleMode {
                host.hide()   // 实时翻译在每次请求完成后会 hide（activeTranslationCount 归零）
                host.show()   // 下次输入时再 show
                results.append("  （--cycle：已执行 hide → show）")
            }
            Task { @MainActor in
                do {
                    let (translation, provider) = try await service.translate(item, from: source, to: target)
                    results.append("  #\(index + 1) OK engine=\(provider) → \(translation)")
                } catch {
                    results.append("  #\(index + 1) FAIL → \(error.localizedDescription)")
                    failed = true
                }
                semaphore.signal()
            }
            // 自旋驱动主 RunLoop（绝不阻塞主线程，否则 MainActor/SwUI 任务无法运行）
            let deadline = Date().addingTimeInterval(30)
            var done = false
            while Date() < deadline {
                if semaphore.wait(timeout: .now() + 0.05) == .success { done = true; break }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            if !done {
                results.append("  #\(index + 1) TIMEOUT（30s 无返回——同进程重复请求悬挂）")
                failed = true
                break
            }
        }
        outcome = results.joined(separator: "\n")
        if failed && !outcome.contains("FAIL") { outcome += "\n（存在悬挂）" }

        print("== 结果 ==")
        print(outcome)
        host.hide()
        if failed { return outcome.contains("TIMEOUT") ? 2 : 1 }
        return 0
    }
}
