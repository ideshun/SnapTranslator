import Foundation
import SwiftUI
import Translation

/// Apple 翻译锚点：持有当前请求，由专用翻译锚点窗口中的隐藏锚点视图消费执行
/// （Translation 框架只能通过挂载在窗口上的视图触发 TranslationSession）
///
/// 并发模型（状态全部收敛在 MainActor，杜绝跨 actor 信号量的 defer/await 限制）：
/// - 同一时刻只承载一个在途请求，新请求在 FIFO 等待队列中排队
/// - 槽位获取/释放均在 MainActor 上同步完成，`defer` 可直接释放，任何退出路径都不泄漏
/// - 任务被取消（如 15s 超时引擎的 cancelAll）时，用 withTaskCancellationHandler
///   主动恢复悬挂的 continuation 并让出槽位。
///   ⚠️ 这一点是修复「一次超时后实时/截图翻译全部永久失效」的关键：
///   CheckedContinuation 不响应取消，若被遗弃，外层 TaskGroup（withTimeout）会
///   永远等不到该子任务结束 → 超时永不生效 → 许可泄漏 → 后续所有请求永久挂起。
@MainActor
final class TranslationAnchor: ObservableObject, @unchecked Sendable {
    struct Request: Identifiable {
        let id: UUID
        let text: String
        let source: Locale.Language?
        let target: Locale.Language
        let prepareOnly: Bool
        let continuation: CheckedContinuation<String, Error>
    }

    @Published var request: Request?
    /// 递增触发器：强制 SwiftUI 重新触发 translationTask
    /// 即使 source/target 相同（Configuration 相等），也能通过变化的值触发
    @Published private(set) var trigger: Int = 0

    /// 槽位占用标记（MainActor 隔离）
    private var slotBusy = false

    /// 等待槽位的队列（MainActor 隔离）；continuation 的 Bool 表示是否成功获得槽位
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiting: [Waiter] = []

    /// 使用 identifier 构造 Locale.Language，兼容所有 BCP 47 格式（含 zh-Hans 等复合码）
    private static func localeLanguage(_ language: Language) -> Locale.Language {
        Locale.Language(identifier: language.rawValue)
    }

    /// 翻译文本（source 传 nil 自动检测），并发请求自动排队串行执行
    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        // 排队等槽位；等待期间被取消则直接放弃（不占槽、不悬挂）
        guard await acquireSlot() else { throw CancellationError() }
        defer { releaseSlot() } // 同 actor 同步释放：成功/失败/取消任一路径都不会泄漏槽位

        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request = Request(
                    id: requestID,
                    text: text,
                    source: source.map(Self.localeLanguage),
                    target: Self.localeLanguage(target),
                    prepareOnly: false,
                    continuation: continuation
                )
                trigger += 1
            }
        } onCancel: {
            // 被取消（超时/上层取消）时恢复 continuation，让它以 CancellationError 抛出，
            // 经 defer 释放槽位。若请求已完成，cancelRequest 因 id 不匹配而 no-op。
            Task { @MainActor [weak self] in self?.cancelRequest(id: requestID) }
        }
    }

    /// 触发语言包下载确认弹窗（需 macOS 15+，通过专用翻译锚点窗口触发）
    func prepareLanguages(source: Language?, target: Language) async throws {
        guard await acquireSlot() else { throw CancellationError() }
        defer { releaseSlot() }

        let requestID = UUID()
        _ = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request = Request(
                    id: requestID,
                    text: "",
                    source: source.map(Self.localeLanguage),
                    target: Self.localeLanguage(target),
                    prepareOnly: true,
                    continuation: continuation
                )
                trigger += 1
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRequest(id: requestID) }
        }
    }

    /// 取消未完成请求，避免悬挂（仅取消尚未被处理的请求）
    func cancelPending() {
        guard let pending = request else { return }
        request = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    /// 按 id 取消指定请求（任务取消回调用；已完成或已被取代时 no-op，防双重 resume）
    func cancelRequest(id: UUID) {
        guard let pending = request, pending.id == id else { return }
        request = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    /// 取消一切：在途请求 + 整个等待队列（窗口隐藏时调用，避免僵尸请求排队）
    func cancelAll() {
        cancelPending()
        let pendingWaiters = waiting
        waiting.removeAll()
        for waiter in pendingWaiters {
            waiter.continuation.resume(returning: false) // 未获得槽位 → 调用方抛 CancellationError
        }
    }

    /// 获取槽位；返回 false 表示等待期间被取消
    private func acquireSlot() async -> Bool {
        if !slotBusy {
            slotBusy = true
            return true
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiting.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.removeWaiter(id: waiterID) }
        }
    }

    /// 从等待队列摘除自己并恢复为「未获得」（仅当还没被正常唤醒；已唤醒则 no-op，防双重恢复）
    private func removeWaiter(id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiting.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    /// 释放槽位：优先转交给队首等待者（槽位保持占用，实现 FIFO 串行），否则真正释放
    private func releaseSlot() {
        if let next = waiting.first {
            waiting.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            slotBusy = false
        }
    }
}

/// 隐藏在专用翻译锚点窗口中的视图：变更 configuration 触发 translationTask
///
/// ★ 结构说明：外层只负责按 `trigger` 重建内层视图。`.translationTask` 以 Configuration
/// 相等性判断是否重新触发——同一语言对的后续请求若仅靠 `config = nil → 赋值` 两段式，
/// 两次赋值会被 SwiftUI 合并进同一次渲染，任务标识从未变化，导致第二次起永久不翻译
/// （实测：同进程第 1 次成功、第 2/3 次超时）。用 `.id(trigger)` 强制重建子视图，
/// `@State config` 归零、translationTask 必然重新触发，不再依赖赋值时序。
@available(macOS 15.0, *)
struct TranslationAnchorView: View {
    @ObservedObject var anchor: TranslationAnchor

    var body: some View {
        AnchorSessionView(anchor: anchor)
            .id(anchor.trigger)
    }
}

/// 实际承载 translationTask 的会话视图（由外层按请求重建）
@available(macOS 15.0, *)
private struct AnchorSessionView: View {
    @ObservedObject var anchor: TranslationAnchor
    @State private var config: TranslationSession.Configuration?

    /// 安全完成请求：仅当请求未被取消时才恢复 continuation
    private func finish(
        request: TranslationAnchor.Request,
        result: Result<String, Error>
    ) {
        // 检查请求是否仍然有效（未被 cancelRequest 取消）
        guard anchor.request?.id == request.id else { return }
        anchor.request = nil
        switch result {
        case .success(let value): request.continuation.resume(returning: value)
        case .failure(let error):
            request.continuation.resume(throwing: Self.actionableError(
                error, source: request.source, target: request.target
            ))
        }
    }

    /// 把 Apple 引擎的原始错误转换为用户可操作的提示。
    /// 实测错误签名映射：'Unable to Translate' = 语向不被支持或语言包未安装
    /// （未装包的 zh-Hant→zh-Hans 稳定复现同文案；ja→zh-Hans 正常；ru→zh-Hans 表现为 15s 挂起）。
    private static func actionableError(
        _ error: Error, source: Locale.Language?, target: Locale.Language
    ) -> Error {
        // 同时覆盖两种错误形态：String(describing:) 的枚举驼峰名（unableToTranslate…）
        // 与 localizedDescription 的散文式文案（Unable to Translate）
        let combined = (String(describing: error) + " " + error.localizedDescription).lowercased()
        let unable = combined.contains("unable to translate") || combined.contains("unabletotranslate")
        guard unable else { return error }
        return AppleTranslationError(message:
            "语向 \(displayName(of: source)) → \(displayName(of: target)) 不被 Apple 离线翻译支持或语言包未安装；"
            + "请在「设置 → 引擎」打开系统翻译语言设置下载语言包、更换目标语言，"
            + "或把主引擎从「仅离线（纯本地，永不联网）」切换为「自动（离线优先）」以启用在线引擎回退"
        )
    }

    /// 展示用语言码：languageCode + script 重组（Locale.Language 无 identifier 属性），
    /// 如 zh-Hant / zh-Hans / en；source 为 nil 表示自动检测
    private static func displayName(of language: Locale.Language?) -> String {
        guard let language else { return "自动" }
        var code = language.languageCode?.identifier ?? "?"
        if let script = language.script?.identifier {
            code += "-\(script)"
        }
        return code
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(config) { session in
                guard let request = anchor.request else { return }
                do {
                    if request.prepareOnly {
                        try await session.prepareTranslation()
                        finish(request: request, result: .success(""))
                    } else {
                        // 尝试直接翻译
                        do {
                            let response = try await session.translate(request.text)
                            finish(request: request, result: .success(response.targetText))
                        } catch {
                            // 仅当错误确实与语言包相关时，才触发语言包准备并重试
                            let errorDesc = String(describing: error).lowercased()
                            let languageRelatedKeywords = ["language", "pack", "download", "languagedownload", "unsupported", "not download"]
                            let needsLanguagePack = languageRelatedKeywords.contains { errorDesc.contains($0) }

                            if needsLanguagePack {
                                do {
                                    try await session.prepareTranslation()
                                    let response = try await session.translate(request.text)
                                    finish(request: request, result: .success(response.targetText))
                                } catch let prepareError {
                                    finish(request: request, result: .failure(prepareError))
                                }
                            } else {
                                // 非语言包相关错误，直接上报
                                finish(request: request, result: .failure(error))
                            }
                        }
                    }
                } catch {
                    finish(request: request, result: .failure(error))
                }
            }
            .task {
                // 视图因 .id(trigger) 重建而重新挂载：为当前请求设置配置，驱动 translationTask
                // （挂载时 config 恒为 nil，nil → 新值必然构成变化，杜绝同值不触发问题）
                guard let request = anchor.request else { return }
                config = TranslationSession.Configuration(
                    source: request.source,
                    target: request.target
                )
            }
    }
}

/// Apple 引擎「Unable to Translate」的可操作化错误包装。
/// TranslationService 用 `error.localizedDescription` 拼接失败信息，
/// LocalizedError.errorDescription 即可正确透出到 UI。
struct AppleTranslationError: LocalizedError, CustomStringConvertible {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

/// Apple Translation 框架（macOS 15+），完全离线
@available(macOS 15.0, *)
@MainActor
final class AppleTranslationProvider: TranslationProviding {
    let name = "Apple 系统翻译"

    private let anchor: TranslationAnchor

    init(anchor: TranslationAnchor) {
        self.anchor = anchor
    }

    var isAvailable: Bool { true }

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        try await anchor.translate(text, from: source, to: target)
    }
}
