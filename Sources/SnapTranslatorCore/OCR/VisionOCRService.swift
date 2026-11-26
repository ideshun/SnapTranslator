import AppKit
@preconcurrency import Vision

/// Apple Vision 端上 OCR，完全离线免费
public final class VisionOCRService: Sendable {
    public static let defaultRecognitionLanguages = [
        "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR",
        "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT", "ru-RU", "uk-UA",
    ]

    public init() {}

    /// 构建 OCR 识别语言集：始终包含默认全语种，优先语言前置
    public static func recognitionLanguages(preferring preferred: Language?) -> [String] {
        var languages = defaultRecognitionLanguages
        if let code = preferred?.visionCode {
            languages.removeAll { $0 == code }
            languages.insert(code, at: 0)
        }
        return languages
    }

    /// 识别图片文字，返回行级坐标与 2D 排版分析后的段落块
    public func recognize(_ image: NSImage, languages: [String]? = nil) async throws -> OCRResult {
        guard let cgImage = image.cgImageFast else {
            throw OCRError.invalidImage
        }
        let recognitionLanguages = languages ?? Self.defaultRecognitionLanguages
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> OCRLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return OCRLine(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: OCRResult(lines: lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = recognitionLanguages
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
