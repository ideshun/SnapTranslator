import SwiftUI
import Translation

/// Apple 翻译锚点：持有当前请求，由结果面板窗口中的隐藏锚点视图消费执行
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

    /// 使用 identifier 构造 Locale.Language，兼容所有 BCP 47 格式（含 zh-Hans 等复合码）
    private static func localeLanguage(_ language: Language) -> Locale.Language {
        Locale.Language(identifier: language.rawValue)
    }

    /// 翻译文本（source 传 nil 自动检测）
    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            request = Request(
                text: text,
                source: source.map(Self.localeLanguage),
                target: Self.localeLanguage(target),
                prepareOnly: false,
                continuation: continuation
            )
        }
    }

    /// 触发语言包下载确认弹窗（需 macOS 15+ 且结果面板可见）
    func prepareLanguages(source: Language?, target: Language) async throws {
        _ = try await withCheckedThrowingContinuation { continuation in
            request = Request(
                text: "",
                source: source.map(Self.localeLanguage),
                target: Self.localeLanguage(target),
                prepareOnly: true,
                continuation: continuation
            )
        }
    }

    /// 面板关闭时取消未完成请求，避免悬挂
    func cancelPending() {
        if let pending = request {
            request = nil
            pending.continuation.resume(throwing: CancellationError())
        }
    }
}

/// 隐藏在结果面板中的锚点视图：变更 configuration 触发 translationTask
@available(macOS 15.0, *)
struct TranslationAnchorView: View {
    @ObservedObject var anchor: TranslationAnchor
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(config) { session in
                guard let request = anchor.request else { return }
                do {
                    if request.prepareOnly {
                        try await session.prepareTranslation()
                        request.continuation.resume(returning: "")
                    } else {
                        let response = try await session.translate(request.text)
                        request.continuation.resume(returning: response.targetText)
                    }
                } catch {
                    request.continuation.resume(throwing: error)
                }
            }
            .onChange(of: anchor.request?.id) { _, newID in
                guard let newID else { return }
                guard let request = anchor.request else { return }
                // 先置 nil 再设值：相同语言对时 Configuration 相等，
                // SwiftUI 不会重触发 translationTask，需要强制两段变更
                config = nil
                DispatchQueue.main.async {
                    // 确保 request 仍是本次触发的，避免旧请求覆盖新请求
                    guard anchor.request?.id == newID, let req = anchor.request else { return }
                    config = TranslationSession.Configuration(
                        source: req.source,
                        target: req.target
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
