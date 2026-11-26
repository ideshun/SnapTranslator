import CoreGraphics
import Foundation

/// OCR 单行识别结果（归一化坐标，原点在左下角，与 Vision 一致）
public struct OCRLine: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect

    public init(id: UUID = UUID(), text: String, confidence: Float = 1.0, boundingBox: CGRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// 经 2D 排版聚类后的视觉段落块（用于智能段落合并与 1:1 块级覆盖渲染）
public struct OCRBlock: Identifiable, Equatable, Sendable {
    public let id: Int
    public let lines: [OCRLine]
    public let mergedText: String
    public let boundingBox: CGRect
    public let averageLineHeight: CGFloat
    public let isProminent: Bool

    public init(
        id: Int,
        lines: [OCRLine],
        mergedText: String,
        boundingBox: CGRect,
        averageLineHeight: CGFloat,
        isProminent: Bool
    ) {
        self.id = id
        self.lines = lines
        self.mergedText = mergedText
        self.boundingBox = boundingBox
        self.averageLineHeight = averageLineHeight
        self.isProminent = isProminent
    }
}

/// OCR 完整结果：同时保留原始逐行文本与智能合并段落文本
public struct OCRResult: Sendable {
    public let lines: [OCRLine]
    public let blocks: [OCRBlock]

    public init(lines: [OCRLine], blocks: [OCRBlock]? = nil) {
        self.lines = lines
        self.blocks = blocks ?? OCRLayoutAnalyzer.analyze(lines)
    }

    /// 原始按行拼接文本
    public var rawText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// 智能段落合并后的文本（消除 PDF/网页硬断行与英文连字符断裂）
    public var smartMergedText: String {
        guard !blocks.isEmpty else { return rawText }
        return blocks.map(\.mergedText).joined(separator: "\n\n")
    }

    /// 兼容旧访问方式：默认返回 rawText
    public var fullText: String { rawText }

    public func text(smartMerge: Bool) -> String {
        smartMerge ? smartMergedText : rawText
    }
}

public enum OCRError: LocalizedError, Sendable {
    case invalidImage

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片格式无法识别"
        }
    }
}
