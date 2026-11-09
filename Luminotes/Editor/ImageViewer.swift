import AppKit
import SwiftUI

struct ImageViewer: View {
    let image: NSImage
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero

    var body: some View {
        ZStack {
            WindowGlassBackground()

            ZStack(alignment: .top) {
                ImageCanvas(image: image, zoom: $zoom, pan: $pan)

                toolbar
            }
        }
        .frame(width: 1000, height: 760)
        .onExitCommand {
            dismiss()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plainPointer)
            .help("Close")

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 2) {
                Button {
                    zoom = max(0.25, zoom - 0.2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plainPointer)
                .help("Zoom out")

                Button {
                    zoom = 1
                    pan = .zero
                } label: {
                    Text("Fit")
                        .font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plainPointer)
                .help("Fit image")

                Button {
                    zoom = min(8, zoom + 0.2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plainPointer)
                .help("Zoom in")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .liquidGlassPanel(cornerRadius: 16, tint: .luminotesSidebarTint)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct ImageCanvas: View {
    let image: NSImage
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize

    @State private var panStart: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let fitScale = min(
                proxy.size.width / max(image.size.width, 1),
                proxy.size.height / max(image.size.height, 1)
            )
            let scale = max(0.01, fitScale * zoom)
            let size = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .position(
                        x: proxy.size.width / 2 + pan.width,
                        y: proxy.size.height / 2 + pan.height
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .overlay {
                ImageCanvasEventMonitor(
                    onScroll: { delta, point, command in
                        if command {
                            let factor = min(max(1 + delta.height * 0.01, 0.8), 1.2)
                            applyZoom(by: factor, at: point, in: proxy.size)
                        } else {
                            pan.width += delta.width
                            pan.height += delta.height
                        }
                    },
                    onMagnify: { magnification, point in
                        applyZoom(by: 1 + magnification, at: point, in: proxy.size)
                    }
                )
                .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private func applyZoom(by factor: CGFloat, at point: CGPoint, in size: CGSize) {
        let oldZoom = zoom
        let newZoom = min(max(oldZoom * factor, 0.25), 8)
        guard abs(newZoom - oldZoom) > 0.0001 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let ratio = newZoom / oldZoom

        pan.width = dx - (dx - pan.width) * ratio
        pan.height = dy - (dy - pan.height) * ratio
        zoom = newZoom
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if panStart == nil {
                    panStart = pan
                }
                guard let start = panStart else { return }
                pan = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStart = nil
            }
    }
}

private struct ImageCanvasEventMonitor: NSViewRepresentable {
    let onScroll: (CGSize, CGPoint, Bool) -> Void
    let onMagnify: (CGFloat, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class MonitorView: NSView {
        var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        private var monitor: Any?

        func install(for view: MonitorView) {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .magnify]
            ) { [weak view] event in
                guard let view,
                      let window = view.window,
                      event.window == window else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }

                switch event.type {
                case .scrollWheel:
                    let command = event.modifierFlags.contains(.command)
                        || NSEvent.modifierFlags.contains(.command)
                    view.onScroll?(
                        CGSize(
                            width: event.scrollingDeltaX,
                            height: event.scrollingDeltaY
                        ),
                        point,
                        command
                    )
                    return nil
                case .magnify:
                    view.onMagnify?(event.magnification, point)
                    return nil
                default:
                    return event
                }
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
