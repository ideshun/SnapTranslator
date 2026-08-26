import SwiftUI

/// 框选遮罩视图：全屏半透明遮罩 + 拖拽绘制选区（本地坐标原点在左上角）
struct OverlayView: View {
    let screenFrame: CGRect
    let onSelect: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var selection: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: screenFrame.size))
                if let selection {
                    path.addRect(selection)
                }
            }
            .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))

            if let selection {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)

                Text("\(Int(selection.width)) × \(Int(selection.height))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: selection.midX, y: max(selection.minY - 14, 10))
            } else {
                VStack(spacing: 6) {
                    Text("拖动框选要翻译的区域")
                        .font(.system(size: 16, weight: .medium))
                    Text("松开即开始识别 · 按 ESC 取消")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(16)
                .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .position(x: screenFrame.width / 2, y: screenFrame.height / 2)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = value.startLocation
                    }
                    dragCurrent = value.location
                }
                .onEnded { value in
                    let rect = CGRect(
                        x: min(value.startLocation.x, value.location.x),
                        y: min(value.startLocation.y, value.location.y),
                        width: abs(value.startLocation.x - value.location.x),
                        height: abs(value.startLocation.y - value.location.y)
                    )
                    dragStart = nil
                    dragCurrent = nil
                    // 过小的选区视为误触，取消本次截屏
                    guard rect.width > 6, rect.height > 6 else {
                        onCancel()
                        return
                    }
                    onSelect(toGlobal(rect))
                }
        )
    }

    /// 本地坐标（原点左上）→ 全局 AppKit 坐标（原点左下）
    private func toGlobal(_ rect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
