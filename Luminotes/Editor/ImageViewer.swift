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
                    .padding(.horizontal, 16)
                    .padding(.top, 64)
                    .padding(.bottom, 16)

                toolbar
            }
        }
        .frame(width: 1000, height: 760)
        .overlay(alignment: .bottom) {
            Text("Drag to pan · Pinch or scroll to zoom")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .liquidGlassPanel(cornerRadius: 15, tint: .luminotesSidebarTint)
                .padding(.bottom, 16)
        }
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
            .buttonStyle(.plain)
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
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .help("Fit image")

                Button {
                    zoom = min(8, zoom + 0.2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .position(
                    x: proxy.size.width / 2 + pan.width,
                    y: proxy.size.height / 2 + pan.height
                )
                .gesture(panGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        }
        .clipped()
        .overlay {
            PDFCanvasEventMonitor(
                onScroll: { delta in
                    pan.width += delta.width
                    pan.height += delta.height
                },
                onMagnify: { magnification in
                    zoom = min(max(zoom * (1 + magnification), 0.25), 8)
                }
            )
            .allowsHitTesting(false)
        }
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
