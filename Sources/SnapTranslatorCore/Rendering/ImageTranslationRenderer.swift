import AppKit
import CoreGraphics
import Foundation

/// 1:1 译文覆盖图渲染器（纯 CoreGraphics 线程安全实现，彻底移除已废弃的 NSImage.lockFocus）：
/// - 修复 Retina 2x 坐标错位：全程以 CGImage 像素尺寸渲染，最终以逻辑点尺寸包装返回
/// - 修复 BGRA 通道反色：采样前统一规范化到 RGBA8（premultipliedLast）位图缓冲
/// - 多点中位数背景采样：在文字框四周取 12 个边缘像素的中位数，抗锯齿/描边/噪声干扰极强
/// - 垂直避让算法：多段折行扩高时避免与下方区块重叠
public enum ImageTranslationRenderer {
    public struct NormalizedRGBASampler {
        public let width: Int
        public let height: Int
        private let bytes: [UInt8]
        private static let fallback = CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)

        public init?(cgImage: CGImage) {
            let w = cgImage.width
            let h = cgImage.height
            guard w > 0, h > 0 else { return nil }
            let bytesPerRow = w * 4
            var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

            guard let ctx = CGContext(
                data: &buffer,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return nil }

            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            self.width = w
            self.height = h
            self.bytes = buffer
        }

        public func sampleBackgroundColor(pixelRect: CGRect) -> NSColor {
            guard width > 0, height > 0 else { return NSColor(cgColor: Self.fallback) ?? .white }

            let left = Int(pixelRect.minX)
            let right = Int(pixelRect.maxX)
            let midX = Int(pixelRect.midX)
            let bottom = Int(pixelRect.minY)
            let top = Int(pixelRect.maxY)
            let midY = Int(pixelRect.midY)

            let pad = max(2, min(6, Int(pixelRect.height * 0.15)))
            let points: [(Int, Int)] = [
                (left - pad, top + pad),
                (midX, top + pad),
                (right + pad, top + pad),
                (left - pad, bottom - pad),
                (midX, bottom - pad),
                (right + pad, bottom - pad),
                (left - pad, midY),
                (right + pad, midY),
                (left + Int(pixelRect.width * 0.25), top + pad),
                (left + Int(pixelRect.width * 0.75), top + pad),
                (left + Int(pixelRect.width * 0.25), bottom - pad),
                (left + Int(pixelRect.width * 0.75), bottom - pad),
            ]

            var reds: [UInt8] = []
            var greens: [UInt8] = []
            var blues: [UInt8] = []
            reds.reserveCapacity(points.count)
            greens.reserveCapacity(points.count)
            blues.reserveCapacity(points.count)

            for (px, py) in points {
                let cx = max(0, min(width - 1, px))
                let cyFromBottom = max(0, min(height - 1, py))
                let row = (height - 1) - cyFromBottom
                let offset = (row * width + cx) * 4
                guard offset + 3 < bytes.count else { continue }
                reds.append(bytes[offset])
                greens.append(bytes[offset + 1])
                blues.append(bytes[offset + 2])
            }

            guard !reds.isEmpty else { return NSColor(cgColor: Self.fallback) ?? .white }
            reds.sort()
            greens.sort()
            blues.sort()
            let mid = reds.count / 2
            return NSColor(
                srgbRed: CGFloat(reds[mid]) / 255.0,
                green: CGFloat(greens[mid]) / 255.0,
                blue: CGFloat(blues[mid]) / 255.0,
                alpha: 1.0
            )
        }
    }

    public static func render(
        cgImage: CGImage,
        pointSize: NSSize,
        translation: String,
        ocrLines: [OCRLine],
        translatedBlocks: [String]? = nil
    ) -> NSImage? {
        guard !translation.isEmpty, !ocrLines.isEmpty else { return nil }
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        guard pixelW > 0, pixelH > 0 else { return nil }

        let targetSize = (pointSize.width > 0 && pointSize.height > 0)
            ? pointSize
            : NSSize(width: pixelW, height: pixelH)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        let sampler = NormalizedRGBASampler(cgImage: cgImage)
        let blocks = OCRLayoutAnalyzer.analyze(ocrLines)

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        if let translatedBlocks, translatedBlocks.count == blocks.count, !blocks.isEmpty {
            renderBlocks(blocks: blocks, texts: translatedBlocks, pixelW: pixelW, pixelH: pixelH, sampler: sampler)
        } else {
            let transLines = translation
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let sortedLines = ocrLines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

            if transLines.count == sortedLines.count {
                let overallAvgH = sortedLines.map(\.boundingBox.height).reduce(0, +) / CGFloat(sortedLines.count)
                for (line, text) in zip(sortedLines, transLines) {
                    let isProminent = line.boundingBox.height > overallAvgH * 1.18
                    drawSingleLine(text: text, box: line.boundingBox, pixelW: pixelW, pixelH: pixelH, sampler: sampler, isProminent: isProminent)
                }
            } else if !blocks.isEmpty {
                let mapped = mapLines(transLines, toSectionCount: blocks.count)
                renderBlocks(blocks: blocks, texts: mapped, pixelW: pixelW, pixelH: pixelH, sampler: sampler)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let outCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: outCG, size: targetSize)
    }

    private static func renderBlocks(
        blocks: [OCRBlock],
        texts: [String],
        pixelW: CGFloat,
        pixelH: CGFloat,
        sampler: NormalizedRGBASampler?
    ) {
        var placedRects: [CGRect] = []
        for (block, text) in zip(blocks, texts) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let rect = drawBlock(text: trimmed, block: block, pixelW: pixelW, pixelH: pixelH, sampler: sampler, placedRects: placedRects) {
                placedRects.append(rect)
            }
        }
    }

    private static func drawSingleLine(
        text: String,
        box: CGRect,
        pixelW: CGFloat,
        pixelH: CGFloat,
        sampler: NormalizedRGBASampler?,
        isProminent: Bool
    ) {
        let px = box.minX * pixelW
        let py = box.minY * pixelH
        let pw = box.width * pixelW
        let ph = box.height * pixelH
        guard pw > 4, ph > 4 else { return }

        let bg = sampler?.sampleBackgroundColor(pixelRect: CGRect(x: px, y: py, width: pw, height: ph))
            ?? NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)
        let textColor = contrastingTextColor(for: bg)

        let weight: NSFont.Weight = isProminent ? .semibold : .medium
        var fontSize = max(11.0, ph * (isProminent ? 0.80 : 0.74))
        let minFontSize = max(9.5, fontSize * 0.62)
        let maxDrawW = max(pw + 12, min(pixelW - px - 6, pw * 1.38))

        var font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        var measured = (text as NSString).size(withAttributes: [.font: font])
        while measured.width > maxDrawW && fontSize > minFontSize {
            fontSize -= 0.5
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            measured = (text as NSString).size(withAttributes: [.font: font])
        }

        let padH = max(2.5, ph * 0.1)
        let padW = max(4.0, ph * 0.16)
        let coverX = max(0, px - padW)
        let desiredW = max(pw, measured.width) + padW * 2
        let coverW = min(pixelW - coverX, desiredW)
        let coverH = max(ph, measured.height) + padH * 2
        let coverY = max(0, min(pixelH - coverH, py - padH))
        let coverRect = CGRect(x: coverX, y: coverY, width: coverW, height: coverH)

        bg.setFill()
        NSBezierPath(roundedRect: coverRect, xRadius: 4, yRadius: 4).fill()

        let textRect = CGRect(
            x: coverRect.minX + padW,
            y: coverRect.midY - measured.height / 2,
            width: max(8, coverRect.width - padW * 2),
            height: measured.height
        )
        (text as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: textColor])
    }

    private static func drawBlock(
        text: String,
        block: OCRBlock,
        pixelW: CGFloat,
        pixelH: CGFloat,
        sampler: NormalizedRGBASampler?,
        placedRects: [CGRect]
    ) -> CGRect? {
        let px = block.boundingBox.minX * pixelW
        let py = block.boundingBox.minY * pixelH
        let pw = block.boundingBox.width * pixelW
        let ph = block.boundingBox.height * pixelH
        guard pw > 4, ph > 4 else { return nil }

        let bg = sampler?.sampleBackgroundColor(pixelRect: CGRect(x: px, y: py, width: pw, height: ph))
            ?? NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)
        let textColor = contrastingTextColor(for: bg)

        let baseLineH = block.averageLineHeight * pixelH
        let weight: NSFont.Weight = block.isProminent ? .semibold : .medium
        var fontSize = max(11.0, baseLineH * (block.isProminent ? 0.78 : 0.72))
        let minFontSize = max(9.5, fontSize * 0.62)

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byWordWrapping
        paraStyle.lineSpacing = max(2.0, baseLineH * 0.14)

        let availW = max(pw + 8, min(pixelW - px - 6, pw * 1.28))
        var font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        var measuredH = ph

        while fontSize >= minFontSize {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paraStyle]
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: availW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            measuredH = ceil(bounds.height)
            if measuredH <= ph + max(8, baseLineH * 0.4) || fontSize <= minFontSize {
                break
            }
            fontSize -= 0.5
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }

        let padH = max(3.0, baseLineH * 0.12)
        let padW = max(5.0, baseLineH * 0.18)
        let coverX = max(0, px - padW)
        let coverW = min(pixelW - coverX, availW + padW * 2)
        let totalH = max(ph, measuredH) + padH * 2

        var coverMaxY = min(pixelH, py + ph + padH)
        for placed in placedRects {
            let overlapX = min(placed.maxX, coverX + coverW) - max(placed.minX, coverX)
            if overlapX > 8 && coverMaxY > placed.minY - 2 && py + ph <= placed.maxY {
                coverMaxY = min(coverMaxY, placed.minY - 2)
            }
        }
        let coverMinY = max(0, coverMaxY - totalH)
        let coverRect = CGRect(x: coverX, y: coverMinY, width: coverW, height: max(4, coverMaxY - coverMinY))

        bg.setFill()
        NSBezierPath(roundedRect: coverRect, xRadius: 4, yRadius: 4).fill()

        let textRect = CGRect(
            x: coverRect.minX + padW,
            y: max(coverRect.minY + padH, coverRect.maxY - padH - measuredH),
            width: max(8, coverRect.width - padW * 2),
            height: min(measuredH, max(4, coverRect.height - padH * 2))
        )
        (text as NSString).draw(in: textRect, withAttributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paraStyle,
        ])
        return coverRect
    }

    private static func contrastingTextColor(for background: NSColor) -> NSColor {
        let srgb = background.usingColorSpace(.sRGB) ?? background
        let luminance = srgb.redComponent * 0.299 + srgb.greenComponent * 0.587 + srgb.blueComponent * 0.114
        return luminance > 0.54
            ? NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 0.94)
            : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.96)
    }

    public static func mapLines(_ lines: [String], toSectionCount count: Int) -> [String] {
        guard count > 0 else { return [] }
        if count == 1 { return [lines.joined(separator: "\n")] }
        if count == lines.count { return lines }
        if lines.count < count {
            return (0..<count).map { $0 < lines.count ? lines[$0] : "" }
        }
        var result: [String] = []
        for i in 0..<(count - 1) {
            result.append(lines[i])
        }
        result.append(lines[(count - 1)...].joined(separator: "\n"))
        return result
    }
}
