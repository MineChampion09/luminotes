import AppKit
import SwiftUI
import SwiftUIMath

@MainActor
final class MathImageRenderer {
    static let shared = MathImageRenderer()

    private let cache = NSCache<NSString, NSImage>()

    func image(
        latex: String,
        fontSize: CGFloat,
        color: NSColor,
        displayStyle: Bool = false
    ) -> NSImage? {
        guard !latex.isEmpty else { return nil }

        let appearance = NSApp.effectiveAppearance
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        let rgb = resolved
        let key = "\(latex)|\(fontSize)|\(displayStyle)|\(rgb.redComponent),\(rgb.greenComponent),\(rgb.blueComponent),\(rgb.alphaComponent)" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let swiftUIColor = Color(
            .sRGB,
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            opacity: rgb.alphaComponent
        )

        let content = Math(latex)
            .mathFont(.init(name: .latinModern, size: fontSize))
            .mathTypesettingStyle(displayStyle ? .display : .text)
            .foregroundStyle(swiftUIColor)
            .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
