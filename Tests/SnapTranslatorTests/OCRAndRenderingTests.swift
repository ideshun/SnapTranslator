import AppKit
import CoreGraphics
import XCTest
@testable import SnapTranslatorCore

final class OCRAndRenderingTests: XCTestCase {
    func testOCRLayoutAnalyzerMergesWrappedLinesAndHyphens() {
        let lines = [
            OCRLine(text: "A Great Title", boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.5, height: 0.08)),
            OCRLine(text: "This is an auto-", boundingBox: CGRect(x: 0.1, y: 0.65, width: 0.7, height: 0.04)),
            OCRLine(text: "mated paragraph test.", boundingBox: CGRect(x: 0.1, y: 0.59, width: 0.65, height: 0.04)),
        ]
        let blocks = OCRLayoutAnalyzer.analyze(lines)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].mergedText, "A Great Title")
        XCTAssertTrue(blocks[0].isProminent)
        XCTAssertEqual(blocks[1].mergedText, "This is an automated paragraph test.")
    }

    func testOCRLayoutAnalyzerCJKNoExtraSpace() {
        let lines = [
            OCRLine(text: "轻量级截屏翻译", boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.6, height: 0.05)),
            OCRLine(text: "零第三方依赖。", boundingBox: CGRect(x: 0.1, y: 0.63, width: 0.5, height: 0.05)),
        ]
        let blocks = OCRLayoutAnalyzer.analyze(lines)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].mergedText, "轻量级截屏翻译零第三方依赖。")
    }

    func testOCRLayoutAnalyzerKeepsTwoColumnsSeparate() {
        let lines = [
            OCRLine(text: "Left col line 1", boundingBox: CGRect(x: 0.05, y: 0.80, width: 0.35, height: 0.04)),
            OCRLine(text: "Left col line 2", boundingBox: CGRect(x: 0.05, y: 0.74, width: 0.35, height: 0.04)),
            OCRLine(text: "Right col line 1", boundingBox: CGRect(x: 0.55, y: 0.80, width: 0.35, height: 0.04)),
            OCRLine(text: "Right col line 2", boundingBox: CGRect(x: 0.55, y: 0.74, width: 0.35, height: 0.04)),
        ]
        let blocks = OCRLayoutAnalyzer.analyze(lines)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].mergedText, "Left col line 1 Left col line 2")
        XCTAssertEqual(blocks[1].mergedText, "Right col line 1 Right col line 2")
    }

    func testNormalizedSamplerNoBGRAChannelSwapAndRetinaExact() throws {
        // 构造一个 400x200 的纯红（R=0.85, G=0.15, B=0.10）图像模拟 Retina 2x 截图（点尺寸 200x100）
        let w = 400
        let h = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue // BGRA!
        let ctx = try XCTUnwrap(CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        ctx.setFillColor(red: 0.85, green: 0.15, blue: 0.10, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let cg = try XCTUnwrap(ctx.makeImage())

        let sampler = try XCTUnwrap(ImageTranslationRenderer.NormalizedRGBASampler(cgImage: cg))
        // 在右上象限（pixelX > 200, pixelY > 100）采样
        let sampled = sampler.sampleBackgroundColor(pixelRect: CGRect(x: 240, y: 120, width: 100, height: 30))
        let srgb = try XCTUnwrap(sampled.usingColorSpace(.sRGB))

        // 验证红蓝通道未反色（红显著高于蓝）
        XCTAssertGreaterThan(srgb.redComponent, 0.75)
        XCTAssertLessThan(srgb.blueComponent, 0.20)

        // 验证 1:1 渲染产出合法 NSImage 且点尺寸保留 200x100
        let ocr = [OCRLine(text: "Hello", boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.15))]
        let rendered = try XCTUnwrap(ImageTranslationRenderer.render(
            cgImage: cg,
            pointSize: NSSize(width: 200, height: 100),
            translation: "你好",
            ocrLines: ocr
        ))
        XCTAssertEqual(rendered.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(rendered.size.height, 100, accuracy: 0.5)
    }
}
