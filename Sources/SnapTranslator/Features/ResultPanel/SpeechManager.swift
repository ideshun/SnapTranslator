import AVFoundation
import Combine

/// 语音朗读管理器：用 AVSpeechSynthesizer 朗读文本
/// 支持朗读、暂停、继续、停止、静音
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    private var currentText = ""
    private var currentLanguage: Language?
    @Published private(set) var isPaused = false
    @Published private(set) var isMuted = false
    /// 朗读状态（含暂停时仍为 true），驱动 UI 中暂停/停止按钮的可用性
    @Published private(set) var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 当前是否已暂停
    var isPausedState: Bool { isPaused }

    /// 当前是否静音
    var isMutedState: Bool { isMuted }

    /// 朗读指定文本（按语言选择对应语音）
    /// - Parameters:
    ///   - text: 待朗读文本
    ///   - language: 语言；nil 时尝试自动识别并兜底英文
    func speak(_ text: String, language: Language?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 如果正在朗读且文本相同，不重复朗读
        if isSpeaking && currentText == trimmed {
            return
        }

        // 停止当前朗读，避免重叠
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        currentText = trimmed
        currentLanguage = language
        isPaused = false

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = 0.45
        utterance.volume = isMuted ? 0.0 : 1.0

        // 根据语言选择语音；未识别到语言时用 BCP 47 码自动匹配，兜底英文
        let langCode = language?.rawValue ?? "en"
        if let voice = AVSpeechSynthesisVoice(language: langCode) {
            utterance.voice = voice
        } else if let fallback = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = fallback
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// 暂停当前朗读
    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// 继续朗读
    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// 切换暂停/继续
    func togglePause() {
        if isPaused {
            resume()
        } else if isSpeaking {
            pause()
        }
    }

    /// 停止当前朗读
    func stop() {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentText = ""
        currentLanguage = nil
        isPaused = false
        isSpeaking = false
    }

    /// 切换静音/恢复音量
    func toggleMute() {
        isMuted.toggle()
        // 静音时停止当前朗读
        if isMuted {
            stop()
        }
    }

    /// 朗读选中文本（若为空则朗读完整文本）
    func speakSelection(_ selected: String, fullText: String, language: Language?) {
        let text = selected.isEmpty ? fullText : selected
        speak(text, language: language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.currentText = ""
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = false
        }
    }
}
