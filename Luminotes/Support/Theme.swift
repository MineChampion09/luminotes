import AppKit
import SwiftUI

enum Palette {
    static let page = Color(nsColor: .luminotesPage)
    static let primaryText = Color(nsColor: .luminotesPrimaryText)
    static let secondaryText = Color(nsColor: .luminotesSecondaryText)
    static let tertiaryText = Color(nsColor: .luminotesTertiaryText)
    static let hover = Color(nsColor: .luminotesHover)
    static let gutterHover = Color(nsColor: .luminotesGutterHover)
    static let callout = Color(nsColor: .luminotesCallout)
    static let code = Color(nsColor: .luminotesCode)
    static let border = Color(nsColor: .luminotesBorder)
    static let menu = Color(nsColor: .luminotesMenu)
    static let accent = Color.accentColor
    static let windowTint = Color(nsColor: .luminotesWindowTint)
    static let sidebarTint = Color(nsColor: .luminotesSidebarTint)
    static let selection = Color(nsColor: .luminotesSelection)
}

enum BlockTypography {
    static let bodyFontSizeKey = "Luminotes.bodyFontSize"
    static let lineSpacingKey = "Luminotes.lineSpacing"
    static let defaultBodyFontSize: CGFloat = 16
    static let defaultLineSpacing: CGFloat = 4

    static var storedBodyFontSize: CGFloat {
        let value = UserDefaults.standard.double(forKey: bodyFontSizeKey)
        return value > 0 ? CGFloat(value) : defaultBodyFontSize
    }

    static var storedLineSpacing: CGFloat {
        if let value = UserDefaults.standard.object(forKey: lineSpacingKey) as? Double {
            return CGFloat(value)
        }
        return defaultLineSpacing
    }

    static var textScale: CGFloat {
        max(0.75, min(2, storedBodyFontSize / defaultBodyFontSize))
    }

    static func font(for type: BlockType, bodyFontSize: CGFloat? = nil) -> NSFont {
        let size = bodyFontSize ?? storedBodyFontSize
        let scale = max(0.75, min(2, size / defaultBodyFontSize))

        func scaled(_ base: CGFloat) -> CGFloat {
            max(1, (base * scale).rounded())
        }

        switch type {
        case .paragraph, .bulletedList, .numberedList, .todo, .toggle:
            return .systemFont(ofSize: scaled(16), weight: .regular)
        case .heading1:
            return .systemFont(ofSize: scaled(32), weight: .bold)
        case .heading2:
            return .systemFont(ofSize: scaled(24), weight: .bold)
        case .heading3:
            return .systemFont(ofSize: scaled(20), weight: .semibold)
        case .heading4:
            return .systemFont(ofSize: scaled(17), weight: .semibold)
        case .heading5:
            return .systemFont(ofSize: scaled(15), weight: .semibold)
        case .heading6:
            return .systemFont(ofSize: scaled(13), weight: .semibold)
        case .quote:
            return .systemFont(ofSize: scaled(18), weight: .regular)
        case .callout:
            return .systemFont(ofSize: scaled(15), weight: .regular)
        case .code, .math:
            return .monospacedSystemFont(ofSize: scaled(13.5), weight: .regular)
        case .image:
            return .systemFont(ofSize: scaled(13), weight: .regular)
        case .divider, .table, .pdf, .mermaid:
            return .systemFont(ofSize: scaled(14), weight: .regular)
        }
    }

    static func color(for type: BlockType) -> NSColor {
        switch type {
        case .image:
            return .luminotesSecondaryText
        default:
            return .luminotesPrimaryText
        }
    }

    static func paragraphStyle(
        for type: BlockType,
        justified: Bool = false,
        lineSpacing: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spacing = lineSpacing ?? storedLineSpacing

        switch type {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            style.lineSpacing = min(spacing, 2)
        case .quote:
            style.lineSpacing = spacing + 1
        default:
            style.lineSpacing = spacing
        }

        if justified {
            switch type {
            case .paragraph, .bulletedList, .numberedList, .todo, .toggle, .quote, .callout:
                style.alignment = .justified
                style.hyphenationFactor = 1.0
            default:
                break
            }
        }

        return style
    }

    static func minHeight(for type: BlockType) -> CGFloat {
        let scale = textScale
        let base: CGFloat
        switch type {
        case .heading1: base = 46
        case .heading2: base = 37
        case .heading3: base = 31
        case .heading4: base = 28
        case .heading5: base = 26
        case .heading6: base = 24
        case .code: base = 36
        case .math: base = 30
        case .image: base = 20
        default: base = 26
        }
        return (base * scale).rounded()
    }

    static func topPadding(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1: return 20
        case .heading2: return 16
        case .heading3: return 12
        case .heading4: return 10
        case .heading5, .heading6: return 8
        case .paragraph: return 5
        case .bulletedList, .numberedList, .todo, .toggle: return 2
        case .quote, .callout: return 4
        case .code, .math: return 4
        default: return 1
        }
    }

    static func bottomPadding(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1: return 6
        case .heading2: return 4
        case .heading3: return 2
        case .paragraph: return 5
        case .bulletedList, .numberedList, .todo, .toggle: return 2
        case .quote, .callout: return 4
        default: return 1
        }
    }
}

extension NSColor {
    static let luminotesPage = NSColor.dynamic(
        name: "LuminotesPage",
        light: NSColor(hex: 0xFAFAF9),
        dark: NSColor(hex: 0x191919)
    )

    static let luminotesPrimaryText = NSColor.dynamic(
        name: "LuminotesPrimaryText",
        light: NSColor(hex: 0x37352F),
        dark: NSColor(hex: 0xDADADA)
    )

    static let luminotesSecondaryText = NSColor.dynamic(
        name: "LuminotesSecondaryText",
        light: NSColor(hex: 0x787774),
        dark: NSColor(hex: 0x9A9A97)
    )

    static let luminotesTertiaryText = NSColor.dynamic(
        name: "LuminotesTertiaryText",
        light: NSColor(hex: 0xA6A5A2),
        dark: NSColor(hex: 0x6F6F6C)
    )

    static let luminotesHover = NSColor.dynamic(
        name: "LuminotesHover",
        light: NSColor(calibratedWhite: 0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 1, alpha: 0.045)
    )

    static let luminotesGutterHover = NSColor.dynamic(
        name: "LuminotesGutterHover",
        light: NSColor(calibratedWhite: 0, alpha: 0.06),
        dark: NSColor(calibratedWhite: 1, alpha: 0.08)
    )

    static let luminotesCallout = NSColor.dynamic(
        name: "LuminotesCallout",
        light: NSColor(hex: 0xF4F3F1),
        dark: NSColor(hex: 0x232323)
    )

    static let luminotesCode = NSColor.dynamic(
        name: "LuminotesCode",
        light: NSColor(hex: 0xF6F5F2),
        dark: NSColor(hex: 0x202020)
    )

    static let luminotesBorder = NSColor.dynamic(
        name: "LuminotesBorder",
        light: NSColor(hex: 0xE8E7E4),
        dark: NSColor(hex: 0x333333)
    )

    static let luminotesMenu = NSColor.dynamic(
        name: "LuminotesMenu",
        light: NSColor(hex: 0xFFFFFF),
        dark: NSColor(hex: 0x252525)
    )

    static let luminotesWindowTint = NSColor.dynamic(
        name: "LuminotesWindowTint",
        light: NSColor(hex: 0xF7F7F4, alpha: 0.78),
        dark: NSColor(hex: 0x1B1B1B, alpha: 0.78)
    )

    static let luminotesSidebarTint = NSColor.dynamic(
        name: "LuminotesSidebarTint",
        light: NSColor(calibratedWhite: 0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 1, alpha: 0.045)
    )

    static let luminotesSelection = NSColor.dynamic(
        name: "LuminotesSelection",
        light: NSColor(calibratedWhite: 0, alpha: 0.055),
        dark: NSColor(calibratedWhite: 1, alpha: 0.075)
    )

    static func dynamic(name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension View {
    func luminotesShadow() -> some View {
        shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
    }
}
