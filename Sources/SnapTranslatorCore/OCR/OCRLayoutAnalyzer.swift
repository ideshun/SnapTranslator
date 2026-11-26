import CoreGraphics
import Foundation

/// OCR 2D 排版分析器：
/// 1. 识别阅读顺序（支持多栏/并行区块，避免左右栏互相串行）
/// 2. 按行高一致性、水平对齐与垂直行距聚类视觉段落块
/// 3. 智能拼接折行（修复英文行尾连字符 `word-\nnext`，中/日/韩不插多余空格，拉丁语系补空格）
public enum OCRLayoutAnalyzer {
    public static func analyze(_ rawLines: [OCRLine]) -> [OCRBlock] {
        let lines = rawLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return [] }

        let overallAvgH = lines.map(\.boundingBox.height).reduce(0, +) / CGFloat(lines.count)
        let ordered = sortReadingOrder(lines)

        var groups: [[OCRLine]] = []
        for line in ordered {
            if let groupIndex = findMatchingGroup(for: line, in: groups) {
                groups[groupIndex].append(line)
            } else {
                groups.append([line])
            }
        }

        // 组内按视觉从上到下排序（Vision 坐标系原点在左下，midY 越大越靠上）
        let normalizedGroups = groups.map { group in
            group.sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > min(a.boundingBox.height, b.boundingBox.height) * 0.4 {
                    return a.boundingBox.midY > b.boundingBox.midY
                }
                return a.boundingBox.minX < b.boundingBox.minX
            }
        }

        // 组间按阅读顺序排序（先分栏从上到下，若同行并排则从左到右）
        let sortedGroups = normalizedGroups.sorted { lhs, rhs in
            let lBox = unionBox(lhs)
            let rBox = unionBox(rhs)
            let verticalOverlap = min(lBox.maxY, rBox.maxY) - max(lBox.minY, rBox.minY)
            let minH = min(lBox.height, rBox.height)
            if minH > 0, verticalOverlap > minH * 0.5 {
                return lBox.minX < rBox.minX
            }
            return lBox.maxY > rBox.maxY
        }

        return sortedGroups.enumerated().map { idx, group in
            let box = unionBox(group)
            let avgH = group.map(\.boundingBox.height).reduce(0, +) / CGFloat(group.count)
            return OCRBlock(
                id: idx + 1,
                lines: group,
                mergedText: mergeLines(group),
                boundingBox: box,
                averageLineHeight: avgH,
                isProminent: avgH > overallAvgH * 1.18
            )
        }
    }

    /// 合并同一段落块内的折行文本
    public static func mergeLines(_ lines: [OCRLine]) -> String {
        guard !lines.isEmpty else { return "" }
        var result = ""
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty {
                result = trimmed
                continue
            }
            // 英文行尾连字符断词修复：如 "transla-" + "tion" -> "translation"
            if result.hasSuffix("-"),
               let prevScalar = result.dropLast().unicodeScalars.last,
               let nextScalar = trimmed.unicodeScalars.first,
               CharacterSet.letters.contains(prevScalar),
               CharacterSet.lowercaseLetters.contains(nextScalar) {
                result.removeLast()
                result += trimmed
            } else if shouldInsertSpace(between: result, and: trimmed) {
                result += " " + trimmed
            } else {
                result += trimmed
            }
        }
        return result
    }

    // MARK: - 内部聚类辅助

    private static func sortReadingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        lines.sorted { a, b in
            let yDiff = a.boundingBox.midY - b.boundingBox.midY
            let threshold = min(a.boundingBox.height, b.boundingBox.height) * 0.45
            if abs(yDiff) > threshold {
                return yDiff > 0
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
    }

    /// 查找最适合合并的已有段落组（兼容双栏排版：只合并水平有重叠且左边界相近、垂直紧凑、行高接近的组）
    private static func findMatchingGroup(for line: OCRLine, in groups: [[OCRLine]]) -> Int? {
        var bestIndex: Int?
        var bestGap: CGFloat = .greatestFiniteMagnitude

        for (index, group) in groups.enumerated() {
            guard let last = group.last else { continue }
            let box1 = last.boundingBox
            let box2 = line.boundingBox

            // 1. 行高相似（18% 容差内；标题与正文不混入同一块）
            let maxH = max(box1.height, box2.height)
            guard maxH > 0 else { continue }
            let heightDiff = abs(box1.height - box2.height) / maxH
            guard heightDiff <= 0.18 else { continue }

            // 2. 垂直间距紧凑（新行在上一行下方）
            let avgH = (box1.height + box2.height) / 2
            let vGap = box1.minY - box2.maxY
            guard vGap >= -avgH * 0.35, vGap <= avgH * 1.15 else { continue }

            // 3. 水平重叠检测（防止左右双栏被错误合并）
            let groupBox = unionBox(group)
            let overlapX = min(groupBox.maxX, box2.maxX) - max(groupBox.minX, box2.minX)
            let minW = min(groupBox.width, box2.width)
            let hasHorizontalOverlap = minW > 0 && (overlapX / minW) >= 0.25
            let leftAligned = abs(groupBox.minX - box2.minX) <= max(0.06, avgH * 2.5)
            guard hasHorizontalOverlap || leftAligned else { continue }

            // 4. 列表项独立成块（如 "• ", "- ", "1. " 开头的项不强行吞并到前一段）
            if isListItemStart(line.text) { continue }

            if vGap < bestGap {
                bestGap = vGap
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func isListItemStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("•") || trimmed.hasPrefix("·") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return true
        }
        return trimmed.range(of: #"^\d+[\.\)、]\s*"#, options: .regularExpression) != nil
    }

    private static func unionBox(_ lines: [OCRLine]) -> CGRect {
        guard let first = lines.first else { return .zero }
        return lines.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    private static func shouldInsertSpace(between lhs: String, and rhs: String) -> Bool {
        guard let last = lhs.unicodeScalars.last, let first = rhs.unicodeScalars.first else {
            return false
        }
        if isCJK(last) && isCJK(first) {
            return false
        }
        if isCJK(last) || isCJK(first) {
            // CJK 与中文标点之间不插空格；其余情况保持自然紧凑
            return false
        }
        return true
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, // CJK 标点
             0x3040...0x30FF, // 日文假名
             0x3400...0x4DBF, // CJK 扩展 A
             0x4E00...0x9FFF, // CJK 基本
             0xAC00...0xD7A3, // 韩文谚文
             0xFF00...0xFFEF: // 全角标点
            return true
        default:
            return false
        }
    }
}
