@_spi(Textual) import SwiftUIMath
import AppKit
import SwiftUI

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
            // Math can draw outside its reported layout bounds. Force the ideal
            // size before rasterizing so accents and wide expressions are not
            // cropped by ImageRenderer.
            .fixedSize()
            .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Distance from the math baseline to the bottom of the rendered image.
    /// Used to align inline math with the surrounding text baseline.
    func descent(
        latex: String,
        fontSize: CGFloat,
        displayStyle: Bool = false
    ) -> CGFloat {
        Math.typographicBounds(
            for: latex,
            fitting: ProposedViewSize(width: nil, height: nil),
            font: .init(name: .latinModern, size: fontSize),
            style: displayStyle ? .display : .text
        ).descent
    }
}
