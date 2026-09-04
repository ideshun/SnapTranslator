import Foundation
import SwiftUI
import Translation

/// Apple 翻译锚点：持有当前请求，由专用翻译锚点窗口中的隐藏锚点视图消费执行
/// （Translation 框架只能通过挂载在窗口上的视图触发 TranslationSession）
@MainActor
final class TranslationAnchor: ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
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

    /// 请求串行化信号量：TranslationAnchor 同一时刻只能承载一个请求，
    /// 并发请求（如实时翻译防抖到期时上一请求仍在进行）会互相覆盖导致 continuation 悬挂，
    /// 表现为“第一次能翻译，继续输入就不翻译了”。这里用异步信号量把请求串行化。
    private let requestSemaphore = AsyncSemaphore()

    /// 使用 identifier 构造 Locale.Language，兼容所有 BCP 47 格式（含 zh-Hans 等复合码）
    private static func localeLanguage(_ language: Language) -> Locale.Language {
        Locale.Language(identifier: language.rawValue)
    }

    /// 翻译文本（source 传 nil 自动检测），并发请求自动排队串行执行
    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        await requestSemaphore.acquire()
        defer { requestSemaphore.release() }
        return try await withCheckedThrowingContinuation { continuation in
            request = Request(
                text: text,
                source: source.map(Self.localeLanguage),
                target: Self.localeLanguage(target),
                prepareOnly: false,
                continuation: continuation
            )
            trigger += 1
        }
    }

    /// 触发语言包下载确认弹窗（需 macOS 15+，通过专用翻译锚点窗口触发）
    func prepareLanguages(source: Language?, target: Language) async throws {
        await requestSemaphore.acquire()
        defer { requestSemaphore.release() }
        _ = try await withCheckedThrowingContinuation { continuation in
            request = Request(
                text: "",
                source: source.map(Self.localeLanguage),
                target: Self.localeLanguage(target),
                prepareOnly: true,
                continuation: continuation
            )
            trigger += 1
        }
    }

    /// 取消未完成请求，避免悬挂（仅取消尚未被处理的请求）
    func cancelPending() {
        if let pending = request {
            request = nil
            pending.continuation.resume(throwing: CancellationError())
        }
    }
}

/// 隐藏在专用翻译锚点窗口中的视图：变更 configuration 触发 translationTask
@available(macOS 15.0, *)
struct TranslationAnchorView: View {
    @ObservedObject var anchor: TranslationAnchor
    @State private var config: TranslationSession.Configuration?

    /// 安全完成请求：仅当请求未被取消时才恢复 continuation
    private func finish(
        request: TranslationAnchor.Request,
        result: Result<String, Error>
    ) {
        // 检查请求是否仍然有效（未被 cancelPending 取消）
        guard anchor.request?.id == request.id else { return }
        anchor.request = nil
        switch result {
        case .success(let value): request.continuation.resume(returning: value)
        case .failure(let error): request.continuation.resume(throwing: error)
        }
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
            .onChange(of: anchor.trigger) { _, newTrigger in
                guard newTrigger > 0 else { return }
                guard let request = anchor.request else { return }
                // 强制两段变更：先 nil 再设置，确保相同语言对也能重新触发
                config = nil
                Task { @MainActor in
                    // 确保 request 仍是本次触发的，避免旧请求覆盖新请求
                    guard anchor.request?.id == request.id, let current = anchor.request else { return }
                    config = TranslationSession.Configuration(
                        source: current.source,
                        target: current.target
                    )
                }
            }
    }
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


/// 异步信号量（许可数 1）：配合 TranslationAnchor 把并发请求串行化，
/// 避免新请求覆盖未完成的旧请求导致 continuation 悬挂
private actor AsyncSemaphore {
    private var available = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if available {
            available = false
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            available = true
        }
    }
}
