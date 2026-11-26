import AVFoundation
import Combine
import SnapTranslatorCore

/// 语音朗读管理器：用 AVSpeechSynthesizer 朗读文本
/// 修复竞态：记录 activeUtterance 身份，旧朗读的异步 didCancel 不再误关新朗读状态
@MainActor
final class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    private weak var activeUtterance: AVSpeechUtterance?
    private var currentText = ""

    @Published private(set) var isPaused = false
    @Published private(set) var isMuted = false
    @Published private(set) var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isPausedState: Bool { isPaused }
    var isMutedState: Bool { isMuted }

    func speak(_ text: String, language: Language?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isSpeaking && currentText == trimmed {
            return
        }

        if isSpeaking || synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        currentText = trimmed
        isPaused = false

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = 0.48
        utterance.volume = isMuted ? 0.0 : 1.0

        let langCode = language?.rawValue ?? "en"
        if let voice = AVSpeechSynthesisVoice(language: langCode) {
            utterance.voice = voice
        } else if let fallback = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = fallback
        }

        activeUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func togglePause() {
        if isPaused {
            resume()
        } else if isSpeaking {
            pause()
        }
    }

    func stop() {
        activeUtterance = nil
        if isSpeaking || synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentText = ""
        isPaused = false
        isSpeaking = false
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stop()
        }
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.isPaused = false
            self.currentText = ""
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.isPaused = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.isPaused = false
        }
    }
}
