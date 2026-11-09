import AppKit
import SwiftUI

// MARK: - Cursor feedback

struct PointingHandCursorModifier: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

struct OpenHandCursorModifier: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    NSCursor.openHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }

    func openHandCursor() -> some View {
        modifier(OpenHandCursorModifier())
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let base = configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Palette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .opacity(configuration.isPressed ? 0.78 : (isEnabled ? 1 : 0.45))
            .contentShape(Rectangle())

        let styled = Group {
            if prominent {
                base.background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.accent)
                )
            } else {
                base.glassPanel(cornerRadius: 7)
            }
        }
        .allowsHitTesting(isEnabled)

        if isEnabled {
            styled.pointingHandCursor()
        } else {
            styled
        }
    }
}

struct PlainPointerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let base = configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : (isEnabled ? 1 : 0.45))

        if isEnabled {
            base.pointingHandCursor()
        } else {
            base
        }
    }
}

struct PlainGrabButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let base = configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : (isEnabled ? 1 : 0.45))

        if isEnabled {
            base.openHandCursor()
        } else {
            base
        }
    }
}

extension ButtonStyle where Self == PlainPointerButtonStyle {
    static var plainPointer: PlainPointerButtonStyle { PlainPointerButtonStyle() }
}

extension ButtonStyle where Self == PlainGrabButtonStyle {
    static var plainGrab: PlainGrabButtonStyle { PlainGrabButtonStyle() }
}

struct WindowGlassBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            Palette.windowTint
        }
        .ignoresSafeArea()
    }
}

struct GlassSurface: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.7))
        }
    }
}

@available(macOS 26.0, *)
struct LiquidGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tintColor: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tintColor
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

extension View {
    /// A Liquid Glass surface on macOS 26+, with a material fallback on older
    /// systems. Intended for floating chrome rather than long-form content.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 8)
        }
    }


    /// The real AppKit Liquid Glass material, used for the PDF editor chrome.
    @ViewBuilder
    func liquidGlassPanel(
        cornerRadius: CGFloat = 12,
        tint: NSColor? = nil
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.background(
                LiquidGlassBackground(
                    cornerRadius: cornerRadius,
                    tintColor: tint
                )
            )
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
                )
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        self.buttonStyle(LiquidGlassButtonStyle(prominent: prominent))
    }
}
