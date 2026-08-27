import AppKit
import Vision

struct OCRLine: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    /// 归一化坐标（原点在左下角，Vision 坐标系）
    let boundingBox: CGRect
}

struct OCRResult {
    let lines: [OCRLine]
    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片格式无法识别"
        }
    }
}

/// Apple Vision 端上 OCR，离线免费
final class VisionOCRService {
    static let defaultRecognitionLanguages = [
        "zh-Hans", "en-US", "ja-JP", "ko-KR",
        "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT", "ru-RU",
    ]

    /// 识别图片文字；languages 传 nil 时使用默认多语种集合
    func recognize(_ image: NSImage, languages: [String]? = nil) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
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
