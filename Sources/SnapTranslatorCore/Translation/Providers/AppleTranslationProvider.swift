import Foundation
import SwiftUI
import Translation

/// Apple 翻译锚点：持有当前请求，由专用翻译锚点窗口中的隐藏锚点视图消费执行
/// （Translation 框架只能通过挂载在窗口上的视图触发 TranslationSession）
@MainActor
public final class TranslationAnchor: ObservableObject, @unchecked Sendable {
    public struct Request: Identifiable {
        public let id: UUID
        public let text: String
        public let source: Locale.Language?
        public let target: Locale.Language
        public let prepareOnly: Bool
        public let continuation: CheckedContinuation<String, Error>
    }

    @Published public var request: Request?
    /// 递增触发器：强制 SwiftUI 重建子视图以重新触发 translationTask
    @Published public private(set) var trigger: Int = 0

    private var slotBusy = false

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var waiting: [Waiter] = []

    public init() {}

    private static func localeLanguage(_ language: Language) -> Locale.Language {
        Locale.Language(identifier: language.rawValue)
    }

    public func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        guard await acquireSlot() else { throw CancellationError() }
        defer { releaseSlot() }

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
            Task { @MainActor [weak self] in self?.cancelRequest(id: requestID) }
        }
    }

    public func prepareLanguages(source: Language?, target: Language) async throws {
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

    public func cancelPending() {
        guard let pending = request else { return }
        request = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    public func cancelRequest(id: UUID) {
        guard let pending = request, pending.id == id else { return }
        request = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    public func cancelAll() {
        cancelPending()
        let pendingWaiters = waiting
        waiting.removeAll()
        for waiter in pendingWaiters {
            waiter.continuation.resume(returning: false)
        }
    }

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

    private func removeWaiter(id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiting.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func releaseSlot() {
        if let next = waiting.first {
            waiting.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            slotBusy = false
        }
    }
}

@available(macOS 15.0, *)
public struct TranslationAnchorView: View {
    @ObservedObject var anchor: TranslationAnchor

    public init(anchor: TranslationAnchor) {
        self.anchor = anchor
    }

    public var body: some View {
        AnchorSessionView(anchor: anchor)
            .id(anchor.trigger)
    }
}

@available(macOS 15.0, *)
private struct AnchorSessionView: View {
    @ObservedObject var anchor: TranslationAnchor
    @State private var config: TranslationSession.Configuration?

    private func finish(request: TranslationAnchor.Request, result: Result<String, Error>) {
        guard anchor.request?.id == request.id else { return }
        anchor.request = nil
        switch result {
        case .success(let value):
            request.continuation.resume(returning: value)
        case .failure(let error):
            request.continuation.resume(throwing: Self.actionableError(
                error, source: request.source, target: request.target
            ))
        }
    }

    private static func actionableError(
        _ error: Error, source: Locale.Language?, target: Locale.Language
    ) -> Error {
        let combined = (String(describing: error) + " " + error.localizedDescription).lowercased()
        let unable = combined.contains("unable to translate") || combined.contains("unabletotranslate")
        guard unable else { return error }
        return AppleTranslationError(message:
            "语向 \(displayName(of: source)) → \(displayName(of: target)) 不被 Apple 离线翻译支持或语言包未安装；请在「设置 → 引擎」下载语言包或切换其他引擎"
        )
    }

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
                        do {
                            let response = try await session.translate(request.text)
                            finish(request: request, result: .success(response.targetText))
                        } catch {
                            let errorDesc = String(describing: error).lowercased()
                            let languageRelatedKeywords = ["language", "pack", "download", "languagedownload", "unsupported", "not download"]
                            if languageRelatedKeywords.contains(where: { errorDesc.contains($0) }) {
                                do {
                                    try await session.prepareTranslation()
                                    let response = try await session.translate(request.text)
                                    finish(request: request, result: .success(response.targetText))
                                } catch let prepareError {
                                    finish(request: request, result: .failure(prepareError))
                                }
                            } else {
                                finish(request: request, result: .failure(error))
                            }
                        }
                    }
                } catch {
                    finish(request: request, result: .failure(error))
                }
            }
            .task {
                guard let request = anchor.request else { return }
                config = TranslationSession.Configuration(
                    source: request.source,
                    target: request.target
                )
            }
    }
}

public struct AppleTranslationError: LocalizedError, CustomStringConvertible, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public var description: String { message }
}

/// Apple Translation 框架（macOS 15+），完全离线
@available(macOS 15.0, *)
public final class AppleTranslationProvider: TranslationProviding, @unchecked Sendable {
    public let name = "Apple 系统翻译"
    public let providerID = "apple"
    public let requiresNetwork = false

    private let anchor: TranslationAnchor

    public init(anchor: TranslationAnchor) {
        self.anchor = anchor
    }

    public var isAvailable: Bool { true }

    public func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> String {
        try await anchor.translate(text, from: source, to: target)
    }
}
