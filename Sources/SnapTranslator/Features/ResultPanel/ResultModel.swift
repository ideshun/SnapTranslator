import AppKit
import SwiftUI

/// 结果面板数据模型：一次截屏翻译的完整生命周期
@MainActor
final class ResultModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recognizing
        case translating
        case done
        case failed(String)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case originalImage = "原图"
        case translation = "译文"
        case sideBySide = "并排"

        var id: String { rawValue }
    }

    @Published var phase: Phase = .idle
    @Published var tab: Tab = .sideBySide
    @Published var image: NSImage?
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var sourceLanguage: Language?
    @Published var targetLanguage: Language = .zhHans
    @Published var providerName = ""
    /// 当前文本选区（供收藏按钮），非空时工具条显示「收藏选中」
    @Published var selectedText = ""
    /// 收藏成功后的短暂提示
    @Published var collectNotice = ""

    /// 重试所需的上次请求内容
    private(set) var retryImage: NSImage?
    private(set) var retrySourceText = ""

    func begin(image: NSImage, target: Language) {
        reset()
        self.image = image
        retryImage = image
        targetLanguage = target
        phase = .recognizing
    }

    func recognized(text: String) {
        sourceText = text
        retrySourceText = text
        phase = .translating
    }

    func finished(translation: String, provider: String, source: Language?) {
        translatedText = translation
        providerName = provider
        sourceLanguage = source
        phase = .done
    }

    func failed(_ message: String) {
        phase = .failed(message)
    }

    func reset() {
        phase = .idle
        image = nil
        sourceText = ""
        translatedText = ""
        sourceLanguage = nil
        providerName = ""
        selectedText = ""
        collectNotice = ""
        retrySourceText = ""
    }
}
