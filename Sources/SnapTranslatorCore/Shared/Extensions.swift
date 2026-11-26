import AppKit
import CoreGraphics

/// 文本面板滚动视图：macOS 27 SDK 起 NSScrollView 不再把文本视图宽度自动铺满可视区
/// （程序化创建的 NSTextView 初始宽度保持 0，表现为整个文本面板空白），
/// 在布局时显式把 documentView 宽度同步为可视区宽度
public class TextPaneScrollView: NSScrollView {
    public override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }
        let targetWidth = contentView.frame.width
        if targetWidth > 0, abs(textView.frame.width - targetWidth) > 0.5 {
            textView.frame.size.width = targetWidth
        }
    }
}

public extension NSImage {
    /// 快速、零 TIFF 编解码优先获取 CGImage（回退至 TIFF 以兼容全部表示）
    var cgImageFast: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        if let direct = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return direct
        }
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.cgImage
    }

    /// 兼容旧属性名
    var cgImage: CGImage? { cgImageFast }

    /// 导出 PNG 字节（用于复制译文图与保存文件）
    func pngData() -> Data? {
        guard let cg = cgImageFast else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    /// 导出压缩 JPEG 字节（用于持久化历史缩略图）
    func jpegData(compressionFactor: CGFloat = 0.82) -> Data? {
        guard let cg = cgImageFast else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
}

public extension NSScreen {
    /// 屏幕的 CGDirectDisplayID
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

public extension NSPasteboard {
    /// 清空后写入纯文本
    static func writeString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 清空后写入图片（PNG + TIFF 双格式兼容微信/文档/系统应用）
    static func writeImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = image.pngData() {
            pasteboard.setData(png, forType: .png)
        }
        pasteboard.writeObjects([image])
    }

    /// 从剪贴板读取图片（支持截图、文件 URL、PNG/TIFF 数据）
    static func readImage() -> NSImage? {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], let first = images.first {
            return first
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls {
                if let img = NSImage(contentsOf: url) {
                    return img
                }
            }
        }
        return nil
    }
}
