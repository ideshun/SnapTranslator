import AVFoundation

/// 语音朗读管理器：用 AVSpeechSynthesizer 朗读原文/译文
/// 点击源语言朗读原文，点击目标语言朗读译文
@MainActor
final class SpeechManager {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    /// 朗读指定文本（按语言选择对应语音）
    /// - Parameters:
    ///   - text: 待朗读文本
    ///   - language: 语言；nil 时尝试自动识别并兜底英文
    func speak(_ text: String, language: Language?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 停止当前朗读，避免重叠
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = 0.45
        utterance.volume = 1.0

        // 根据语言选择语音；未识别到语言时用 BCP 47 码自动匹配，兜底英文
        let langCode = language?.rawValue ?? "en"
        if let voice = AVSpeechSynthesisVoice(language: langCode) {
            utterance.voice = voice
        } else if let fallback = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = fallback
        }

        synthesizer.speak(utterance)
    }

    /// 停止当前朗读
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
