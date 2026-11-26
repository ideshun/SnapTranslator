import SwiftUI

/// 单次截屏遮罩会话状态（在 OverlayWindow 与 OverlayView 之间共享）
@MainActor
final class OverlaySessionState: ObservableObject {
    @Published var action: CaptureAction
    @Published var refineMode: Bool
    @Published var lockedSelection: CGRect?

    init(action: CaptureAction, refineMode: Bool) {
        self.action = action
        self.refineMode = refineMode
    }
}

/// 精致框选遮罩视图：CleanShot X 质感毛玻璃顶部模式坞 + 精致选区发光边框 + 实时尺寸胶囊 + 精调手柄
struct OverlayView: View {
    let screenFrame: CGRect
    var snapshot: NSImage?
    @ObservedObject var state: OverlaySessionState
    let onSelect: (CGRect, CGRect, CaptureAction) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var moveOriginRect: CGRect?

    private var activeSelection: CGRect? {
        if let locked = state.lockedSelection { return locked }
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
            // ① 全屏静止定格底图
            if let snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenFrame.width, height: screenFrame.height)
                    .position(x: screenFrame.width / 2, y: screenFrame.height / 2)
            }

            // ② 柔暗色遮罩（选区精准镂空）
            Path { path in
                path.addRect(CGRect(origin: .zero, size: screenFrame.size))
                if let selection = activeSelection {
                    path.addRect(selection)
                }
            }
            .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))

            // ③ 自由拉框手势层
            if state.lockedSelection == nil {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = value.startLocation }
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
                                guard rect.width > 6, rect.height > 6 else {
                                    onCancel()
                                    return
                                }
                                if state.refineMode {
                                    state.lockedSelection = rect
                                } else {
                                    onSelect(toGlobal(rect), rect, state.action)
                                }
                            }
                    )
            }

            // ④ 选区发光边框、精密尺寸标签与精调手柄
            if let selection = activeSelection {
                // 双层边框：外层细微主题光晕 + 内层纯白锐利描边
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.85), lineWidth: 2.5)
                    .frame(width: selection.width + 2, height: selection.height + 2)
                    .position(x: selection.midX, y: selection.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .allowsHitTesting(false)

                // 尺寸胶囊
                HStack(spacing: 4) {
                    Text("\(Int(selection.width)) × \(Int(selection.height))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text("pt")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .position(x: max(56, min(screenFrame.width - 56, selection.midX)), y: max(selection.minY - 18, 66))
                .allowsHitTesting(false)

                if let locked = state.lockedSelection {
                    refineOverlay(for: locked)
                }
            } else {
                // 优雅底部轻量提示胶囊（不再遮挡屏幕中央目标内容！）
                HStack(spacing: 10) {
                    Image(systemName: state.action.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("拖动框选区域，或单击窗口自动吸附")
                        .font(.system(size: 13, weight: .medium))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.45))
                    Text("ESC / 右键取消")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Capsule().fill(Color.black.opacity(0.52)))
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.32), radius: 12, y: 4)
                .position(x: screenFrame.width / 2, y: screenFrame.height - 54)
                .allowsHitTesting(false)
            }

            // ⑤ 顶部毛玻璃模式坞
            topModeBar
                .position(x: screenFrame.width / 2, y: 36)
        }
    }

    private var topModeBar: some View {
        HStack(spacing: 4) {
            ForEach(CaptureAction.allCases) { item in
                let selected = state.action == item
                Button { state.action = item } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 4)

            Button { state.refineMode.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.refineMode ? "crop" : "bolt.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(state.refineMode ? "精调" : "即刻")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(state.refineMode ? Color.yellow : Color.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(state.refineMode ? 0.18 : 0.08))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(4.5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
    }

    @ViewBuilder
    private func refineOverlay(for rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if moveOriginRect == nil { moveOriginRect = rect }
                        guard let base = moveOriginRect else { return }
                        let nx = max(0, min(screenFrame.width - base.width, base.origin.x + value.translation.width))
                        let ny = max(0, min(screenFrame.height - base.height, base.origin.y + value.translation.height))
                        state.lockedSelection = CGRect(x: nx, y: ny, width: base.width, height: base.height)
                    }
                    .onEnded { _ in moveOriginRect = nil }
            )

        cornerHandle(at: CGPoint(x: rect.minX, y: rect.minY)) { dx, dy in
            updateRect(rect, minX: rect.minX + dx, minY: rect.minY + dy, maxX: rect.maxX, maxY: rect.maxY)
        }
        cornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY)) { dx, dy in
            updateRect(rect, minX: rect.minX, minY: rect.minY + dy, maxX: rect.maxX + dx, maxY: rect.maxY)
        }
        cornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY)) { dx, dy in
            updateRect(rect, minX: rect.minX + dx, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY + dy)
        }
        cornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY)) { dx, dy in
            updateRect(rect, minX: rect.minX, minY: rect.minY, maxX: rect.maxX + dx, maxY: rect.maxY + dy)
        }

        let barY = (rect.maxY + 48 < screenFrame.height) ? rect.maxY + 28 : max(72, rect.minY - 28)
        let barX = max(190, min(screenFrame.width - 190, rect.midX))

        HStack(spacing: 5) {
            ForEach(CaptureAction.allCases) { item in
                Button { onSelect(toGlobal(rect), rect, item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.iconName).font(.system(size: 11, weight: .semibold))
                        Text(item.rawValue).font(.system(size: 11.5, weight: item == state.action ? .semibold : .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(item == state.action ? Color.accentColor : Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.black.opacity(0.58)))
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .position(x: barX, y: barY)
    }

    private func cornerHandle(at point: CGPoint, onDrag: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 11, height: 11)
            .position(point)
            .gesture(DragGesture().onChanged { value in onDrag(value.translation.width, value.translation.height) })
    }

    private func updateRect(_ original: CGRect, minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let clampedMinX = max(0, min(minX, maxX - 16))
        let clampedMinY = max(0, min(minY, maxY - 16))
        let clampedMaxX = min(screenFrame.width, max(maxX, clampedMinX + 16))
        let clampedMaxY = min(screenFrame.height, max(maxY, clampedMinY + 16))
        state.lockedSelection = CGRect(
            x: clampedMinX,
            y: clampedMinY,
            width: clampedMaxX - clampedMinX,
            height: clampedMaxY - clampedMinY
        )
    }

    private func toGlobal(_ rect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
