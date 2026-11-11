import AppKit
import PDFKit
import SwiftUI

struct PDFPageGeometry: Equatable {
    var pageRect: CGRect
    var pageBounds: CGRect
    var pageIndex: Int
}

@MainActor
final class PDFCanvasInteraction: ObservableObject {
    @Published var pan: CGSize = .zero

    func scroll(delta: CGSize) {
        pan.width += delta.width
        pan.height += delta.height
    }
}


struct PDFTextBox: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var page: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var text: String
    var fontSize: Double
    var fontName: String
    var colorHex: String
    var backgroundColorHex: String

    init(
        id: UUID = UUID(),
        page: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        text: String,
        fontSize: Double = 14,
        fontName: String = "system",
        colorHex: String = "#000000",
        backgroundColorHex: String = "#00000000"
    ) {
        self.id = id
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.fontSize = fontSize
        self.fontName = fontName
        self.colorHex = colorHex
        self.backgroundColorHex = backgroundColorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, page, x, y, width, height, text, fontSize, fontName, colorHex, backgroundColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.15
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.15
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0.4
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0.1
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "system"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#000000"
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#00000000"
    }
}

struct PDFMathBox: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var page: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var latex: String
    var colorHex: String
    var backgroundColorHex: String

    init(
        id: UUID = UUID(),
        page: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        latex: String = "",
        colorHex: String = "#000000",
        backgroundColorHex: String = "#00000000"
    ) {
        self.id = id
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.latex = latex
        self.colorHex = colorHex
        self.backgroundColorHex = backgroundColorHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, page, x, y, width, height, latex, colorHex, backgroundColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 0
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.15
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.15
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0.3
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 0.12
        latex = try container.decodeIfPresent(String.self, forKey: .latex) ?? ""
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#000000"
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#00000000"
    }
}

struct PDFAnnotationFile: Codable {
    var version: Int
    var textBoxes: [PDFTextBox]
    var mathBoxes: [PDFMathBox]

    init(
        version: Int = 1,
        textBoxes: [PDFTextBox] = [],
        mathBoxes: [PDFMathBox] = []
    ) {
        self.version = version
        self.textBoxes = textBoxes
        self.mathBoxes = mathBoxes
    }

    private enum CodingKeys: String, CodingKey {
        case version, textBoxes, mathBoxes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        textBoxes = try container.decodeIfPresent([PDFTextBox].self, forKey: .textBoxes) ?? []
        mathBoxes = try container.decodeIfPresent([PDFMathBox].self, forKey: .mathBoxes) ?? []
    }
}

enum PDFAnnotationStore {
    static func sidecarURL(for pdfURL: URL) -> URL {
        pdfURL.deletingLastPathComponent()
            .appendingPathComponent(pdfURL.lastPathComponent + ".luminotes.json")
    }

    static func load(for pdfURL: URL) -> PDFAnnotationFile {
        guard let data = try? Data(contentsOf: sidecarURL(for: pdfURL)),
              let file = try? JSONDecoder().decode(PDFAnnotationFile.self, from: data) else {
            return PDFAnnotationFile()
        }
        return file
    }

    static func save(_ file: PDFAnnotationFile, for pdfURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: sidecarURL(for: pdfURL), options: .atomic)
    }
}

struct PDFPageCanvas: View {
    let document: PDFDocument
    let pageIndex: Int
    let boxes: [PDFTextBox]
    var mathBoxes: [PDFMathBox] = []
    var isEditable = false
    var selectedBoxID: UUID?
    var selectedMathBoxID: UUID?
    @Binding var editingBoxID: UUID?
    var zoom: CGFloat = 1
    var fitsHeight: CGFloat?
    var topInset: CGFloat = 0
    var isPlacingTextBox = false
    var isPlacingMathBox = false
    var onPlaceTextBox: ((CGPoint) -> Void)?
    var onPlaceMathBox: ((CGPoint) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    var onSelect: (UUID?) -> Void = { _ in }
    var onChange: (PDFTextBox) -> Void = { _ in }
    var onSelectMath: (UUID?) -> Void = { _ in }
    var onChangeMath: (PDFMathBox) -> Void = { _ in }
    var onBeginEditingMath: (UUID) -> Void = { _ in }

    @State private var pageImage: NSImage?
    @State private var pageBounds: CGRect = .zero
    @State private var loadToken = UUID()
    @StateObject private var interaction = PDFCanvasInteraction()
    @State private var panStart: CGSize?

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 12
        return cache
    }()

    var body: some View {
        GeometryReader { proxy in
            if let pageImage, pageBounds.width > 0, pageBounds.height > 0 {
                let fitHeight = fitsHeight ?? max(1, proxy.size.height - topInset)
                let fitScale = min(
                    proxy.size.width / pageBounds.width,
                    fitHeight / pageBounds.height
                )
                let scale = fitsHeight == nil ? fitScale * zoom : fitScale
                let imageSize = CGSize(
                    width: pageBounds.width * scale,
                    height: pageBounds.height * scale
                )

                let content = ZStack(alignment: .topLeading) {
                    pageImageView(
                        pageImage,
                        size: imageSize,
                        pannable: fitsHeight == nil,
                        isPlacing: isPlacingTextBox || isPlacingMathBox,
                        onPlace: { point in
                            if isPlacingTextBox {
                                onPlaceTextBox?(point)
                            } else if isPlacingMathBox {
                                onPlaceMathBox?(point)
                            }
                        },
                        onBackgroundTap: isEditable ? { editingBoxID = nil } : nil
                    )
                        .frame(width: imageSize.width, height: imageSize.height)
                        .background(Color.white)

                    PDFTextBoxOverlay(
                        boxes: boxes,
                        page: pageIndex,
                        geometry: PDFPageGeometry(
                            pageRect: CGRect(origin: .zero, size: imageSize),
                            pageBounds: pageBounds,
                            pageIndex: pageIndex
                        ),
                        isEditable: isEditable,
                        selectedBoxID: selectedBoxID,
                        editingBoxID: $editingBoxID,
                        onSelect: onSelect,
                        onChange: onChange
                    )
                    .frame(width: imageSize.width, height: imageSize.height)
                    .allowsHitTesting(isEditable && !isPlacingTextBox && !isPlacingMathBox)

                    PDFMathBoxOverlay(
                        boxes: mathBoxes,
                        page: pageIndex,
                        geometry: PDFPageGeometry(
                            pageRect: CGRect(origin: .zero, size: imageSize),
                            pageBounds: pageBounds,
                            pageIndex: pageIndex
                        ),
                        isEditable: isEditable,
                        selectedBoxID: selectedMathBoxID,
                        onSelect: onSelectMath,
                        onChange: onChangeMath,
                        onBeginEditing: onBeginEditingMath
                    )
                    .frame(width: imageSize.width, height: imageSize.height)
                    .allowsHitTesting(isEditable && !isPlacingTextBox && !isPlacingMathBox)
                }
                .frame(width: imageSize.width, height: imageSize.height)

                if fitsHeight == nil {
                    content
                        .position(
                            x: proxy.size.width / 2 + interaction.pan.width,
                            y: topInset + fitHeight / 2 + interaction.pan.height
                        )
                        .clipped()
                } else {
                    content
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                        .clipped()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .overlay {
            if fitsHeight == nil {
                PDFCanvasEventMonitor(
                    onScroll: { delta in
                        interaction.scroll(delta: delta)
                    },
                    onMagnify: { magnification in
                        let newZoom = min(max(zoom * (1 + magnification), 0.5), 4)
                        onZoomChange?(newZoom)
                    }
                )
                .allowsHitTesting(false)
            }
        }
        .onAppear(perform: loadPage)
        .onChange(of: pageIndex) { _, _ in loadPage() }
        .onChange(of: document) { _, _ in loadPage() }
    }

    @ViewBuilder
    private func pageImageView(
        _ image: NSImage,
        size: CGSize,
        pannable: Bool,
        isPlacing: Bool,
        onPlace: ((CGPoint) -> Void)?,
        onBackgroundTap: (() -> Void)?
    ) -> some View {
        let view = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)

        if isPlacing {
            view
                .contentShape(Rectangle())
                .highPriorityGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard size.width > 0, size.height > 0 else { return }
                            onPlace?(
                                CGPoint(
                                    x: value.location.x / size.width,
                                    y: value.location.y / size.height
                                )
                            )
                        }
                )
        } else if pannable {
            view
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture {
                    onBackgroundTap?()
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        } else {
            view
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if panStart == nil {
                    panStart = interaction.pan
                }
                guard let start = panStart else { return }
                interaction.pan = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
            }
            .onEnded { _ in
                panStart = nil
            }
    }

    private func loadPage() {
        guard let page = document.page(at: pageIndex) else {
            pageImage = nil
            pageBounds = .zero
            return
        }

        let token = UUID()
        loadToken = token
        // PDFKit's thumbnail honors the page's /Rotate value, so the layout
        // size must be the rotated display size, not the raw crop box.
        let displayBounds = Self.displayBounds(for: page)
        pageBounds = displayBounds

        let targetSize = CGSize(
            width: max(1, displayBounds.width * 3),
            height: max(1, displayBounds.height * 3)
        )
        let key = "\(ObjectIdentifier(document))-\(pageIndex)-\(page.rotation)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        if let cached = Self.imageCache.object(forKey: key) {
            pageImage = cached
            return
        }

        pageImage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let image = page.thumbnail(of: targetSize, for: .cropBox)

            DispatchQueue.main.async {
                guard loadToken == token else { return }
                Self.imageCache.setObject(image, forKey: key)
                pageImage = image
            }
        }
    }

    /// The size a page occupies after PDFKit applies its rotation. Pages
    /// scanned sideways commonly carry a 90-degree / 270-degree rotation, for
    /// which the crop box and the displayed image have swapped dimensions.
    private static func displayBounds(for page: PDFPage) -> CGRect {
        let bounds = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        guard rotation == 90 || rotation == 270 else {
            return bounds
        }
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.height,
            height: bounds.width
        )
    }
}

struct PDFTextBoxOverlay: View {
    let boxes: [PDFTextBox]
    let page: Int
    let geometry: PDFPageGeometry
    var isEditable = false
    var selectedBoxID: UUID?
    @Binding var editingBoxID: UUID?
    var onSelect: (UUID?) -> Void = { _ in }
    var onChange: (PDFTextBox) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(boxes.filter { $0.page == page && (isEditable || !$0.text.isEmpty) }) { box in
                PDFTextBoxView(
                    box: box,
                    geometry: geometry,
                    isEditable: isEditable,
                    isSelected: selectedBoxID == box.id,
                    editingBoxID: $editingBoxID,
                    onSelect: { onSelect(box.id) },
                    onChange: onChange
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(isEditable)
    }
}

private enum ResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private struct PDFTextBoxView: View {
    let box: PDFTextBox
    let geometry: PDFPageGeometry
    let isEditable: Bool
    let isSelected: Bool
    @Binding var editingBoxID: UUID?
    let onSelect: () -> Void
    let onChange: (PDFTextBox) -> Void

    @State private var dragOrigin: PDFTextBox?
    @State private var dragTranslation: CGSize = .zero
    @State private var resizeOrigin: PDFTextBox?
    @State private var resizeTranslation: CGSize = .zero
    @State private var resizeCorner: ResizeCorner?
    @State private var draft = ""

    private var pageScale: CGFloat {
        guard geometry.pageBounds.width > 0 else { return 1 }
        return geometry.pageRect.width / geometry.pageBounds.width
    }

    /// Font size in PDF points. The whole text-box content is rendered at this
    /// size and then scaled as a unit, so zooming never reflows the text.
    private var fontSize: CGFloat {
        max(6, box.fontSize)
    }

    private var textFont: Font {
        if box.fontName == "system" {
            return .system(size: fontSize)
        }
        return .custom(box.fontName, size: fontSize)
    }

    private var textColor: Color {
        Color(hex: box.colorHex) ?? .black
    }

    private var backgroundColor: Color {
        Color(hex: box.backgroundColorHex) ?? .clear
    }

    private var displayBox: PDFTextBox {
        if let origin = resizeOrigin, let corner = resizeCorner {
            return resizedBox(origin: origin, translation: resizeTranslation, corner: corner)
        }
        if let origin = dragOrigin {
            return movedBox(origin: origin, translation: dragTranslation)
        }
        return box
    }

    private var displayRect: CGRect {
        let current = displayBox
        return CGRect(
            x: geometry.pageRect.minX + current.x * geometry.pageRect.width,
            y: geometry.pageRect.minY + current.y * geometry.pageRect.height,
            width: current.width * geometry.pageRect.width,
            height: current.height * geometry.pageRect.height
        )
    }

    private var nsFont: NSFont {
        if box.fontName == "system" {
            return .systemFont(ofSize: fontSize)
        }
        return NSFont(name: box.fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    private var nsColor: NSColor {
        guard let cgColor = textColor.cgColor,
              let color = NSColor(cgColor: cgColor) else {
            return .black
        }
        return color
    }

    /// The text-box size in PDF points. Scaling this by `pageScale` produces
    /// exactly `displayRect`, so the content and the selection chrome agree.
    private var baseSize: CGSize {
        let scale = max(pageScale, 0.0001)
        return CGSize(
            width: displayRect.width / scale,
            height: displayRect.height / scale
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            boxContent
                .frame(width: baseSize.width, height: baseSize.height, alignment: .topLeading)
                .clipped()
                .scaleEffect(pageScale, anchor: .topLeading)
                .frame(width: displayRect.width, height: displayRect.height, alignment: .topLeading)

            if isEditable && isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .allowsHitTesting(false)

                resizeHandle(.topLeft)
                resizeHandle(.topRight)
                resizeHandle(.bottomLeft)
                resizeHandle(.bottomRight)
            }
        }
        .frame(
            width: displayRect.width,
            height: displayRect.height,
            alignment: .topLeading
        )
        .position(x: displayRect.midX, y: displayRect.midY)
        .onChange(of: editingBoxID) { old, new in
            if new == box.id {
                draft = box.text
            } else if old == box.id {
                commitEditing()
            }
        }
    }

    @ViewBuilder
    private var boxContent: some View {
        Group {
            if isEditable && editingBoxID == box.id {
                PDFTextBoxInlineEditor(
                    text: $draft,
                    font: nsFont,
                    color: nsColor,
                    onCommit: commitEditing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(box.text.isEmpty ? (isEditable ? "Text" : "") : box.text)
                    .font(textFont)
                    .foregroundStyle(box.text.isEmpty ? Color.secondary : textColor)
                    .lineLimit(nil)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if isEditable { beginEditing() }
                    }
                    .onTapGesture {
                        if isEditable { onSelect() }
                    }
                    .gesture(isEditable ? moveGesture : nil)
                    .onHover { hovering in
                        guard isEditable else { return }
                        if hovering {
                            NSCursor.openHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
            }
        }
        .background(backgroundColor)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = box
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard let origin = dragOrigin else {
                    dragTranslation = .zero
                    return
                }
                let updated = movedBox(origin: origin, translation: value.translation)
                onChange(updated)
                dragOrigin = nil
                dragTranslation = .zero
            }
    }

    private func movedBox(origin: PDFTextBox, translation: CGSize) -> PDFTextBox {
        guard geometry.pageRect.width > 0, geometry.pageRect.height > 0 else {
            return origin
        }
        var updated = origin
        let dx = translation.width / geometry.pageRect.width
        let dy = translation.height / geometry.pageRect.height
        updated.x = min(max(0, origin.x + dx), max(0, 1 - updated.width))
        updated.y = min(max(0, origin.y + dy), max(0, 1 - updated.height))
        return updated
    }

    private func resizeHandle(_ corner: ResizeCorner) -> some View {
        let point: CGPoint
        switch corner {
        case .topLeft:
            point = CGPoint(x: 6, y: 6)
        case .topRight:
            point = CGPoint(x: displayRect.width - 6, y: 6)
        case .bottomLeft:
            point = CGPoint(x: 6, y: displayRect.height - 6)
        case .bottomRight:
            point = CGPoint(x: displayRect.width - 6, y: displayRect.height - 6)
        }

        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
            .frame(width: 7, height: 7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(corner))
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    private func resizeGesture(_ corner: ResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if resizeOrigin == nil {
                    resizeOrigin = box
                    resizeCorner = corner
                }
                resizeTranslation = value.translation
            }
            .onEnded { value in
                guard let origin = resizeOrigin, resizeCorner == corner else {
                    resizeTranslation = .zero
                    return
                }
                let updated = resizedBox(origin: origin, translation: value.translation, corner: corner)
                onChange(updated)
                resizeOrigin = nil
                resizeTranslation = .zero
                resizeCorner = nil
            }
    }

    private func resizedBox(
        origin: PDFTextBox,
        translation: CGSize,
        corner: ResizeCorner
    ) -> PDFTextBox {
        guard geometry.pageRect.width > 0, geometry.pageRect.height > 0 else {
            return origin
        }

        let dx = translation.width / geometry.pageRect.width
        let dy = translation.height / geometry.pageRect.height
        let minWidth = 0.05
        let minHeight = 0.03

        var x = origin.x
        var y = origin.y
        var width = origin.width
        var height = origin.height

        switch corner {
        case .bottomRight:
            width = max(minWidth, origin.width + dx)
            height = max(minHeight, origin.height + dy)
        case .bottomLeft:
            x = min(max(0, origin.x + dx), origin.x + origin.width - minWidth)
            width = origin.x + origin.width - x
            height = max(minHeight, origin.height + dy)
        case .topRight:
            width = max(minWidth, origin.width + dx)
            y = min(max(0, origin.y + dy), origin.y + origin.height - minHeight)
            height = origin.y + origin.height - y
        case .topLeft:
            x = min(max(0, origin.x + dx), origin.x + origin.width - minWidth)
            width = origin.x + origin.width - x
            y = min(max(0, origin.y + dy), origin.y + origin.height - minHeight)
            height = origin.y + origin.height - y
        }

        var updated = origin
        updated.x = x
        updated.y = y
        updated.width = min(max(minWidth, width), 1 - x)
        updated.height = min(max(minHeight, height), 1 - y)
        return updated
    }

    private func beginEditing() {
        draft = box.text
        editingBoxID = box.id
    }

    private func commitEditing() {
        var updated = box
        updated.text = draft
        onChange(updated)
        editingBoxID = nil
    }
}

struct PDFMathBoxOverlay: View {
    let boxes: [PDFMathBox]
    let page: Int
    let geometry: PDFPageGeometry
    var isEditable = false
    var selectedBoxID: UUID?
    var onSelect: (UUID?) -> Void = { _ in }
    var onChange: (PDFMathBox) -> Void = { _ in }
    var onBeginEditing: (UUID) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(boxes.filter { $0.page == page && (isEditable || !$0.latex.isEmpty) }) { box in
                PDFMathBoxView(
                    box: box,
                    geometry: geometry,
                    isEditable: isEditable,
                    isSelected: selectedBoxID == box.id,
                    onSelect: { onSelect(box.id) },
                    onChange: onChange,
                    onBeginEditing: { onBeginEditing(box.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(isEditable)
    }
}

private struct PDFMathBoxView: View {
    let box: PDFMathBox
    let geometry: PDFPageGeometry
    let isEditable: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onChange: (PDFMathBox) -> Void
    let onBeginEditing: () -> Void

    @State private var dragOrigin: PDFMathBox?
    @State private var dragTranslation: CGSize = .zero
    @State private var resizeOrigin: PDFMathBox?
    @State private var resizeTranslation: CGSize = .zero
    @State private var resizeCorner: ResizeCorner?

    private var pageScale: CGFloat {
        guard geometry.pageBounds.width > 0 else { return 1 }
        return geometry.pageRect.width / geometry.pageBounds.width
    }

    private var textColor: Color {
        Color(hex: box.colorHex) ?? .black
    }

    private var backgroundColor: Color {
        Color(hex: box.backgroundColorHex) ?? .clear
    }

    private var nsColor: NSColor {
        guard let cgColor = textColor.cgColor,
              let color = NSColor(cgColor: cgColor) else {
            return .black
        }
        return color
    }

    private var mathImage: NSImage? {
        guard !box.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return MathImageRenderer.shared.image(
            latex: box.latex,
            fontSize: 24,
            color: nsColor,
            displayStyle: true
        )
    }

    private var displayBox: PDFMathBox {
        if let origin = resizeOrigin, let corner = resizeCorner {
            return resizedBox(origin: origin, translation: resizeTranslation, corner: corner)
        }
        if let origin = dragOrigin {
            return movedBox(origin: origin, translation: dragTranslation)
        }
        return box
    }

    private var displayRect: CGRect {
        let current = displayBox
        return CGRect(
            x: geometry.pageRect.minX + current.x * geometry.pageRect.width,
            y: geometry.pageRect.minY + current.y * geometry.pageRect.height,
            width: current.width * geometry.pageRect.width,
            height: current.height * geometry.pageRect.height
        )
    }

    private var baseSize: CGSize {
        let scale = max(pageScale, 0.0001)
        return CGSize(
            width: displayRect.width / scale,
            height: displayRect.height / scale
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            boxContent
                .frame(width: baseSize.width, height: baseSize.height, alignment: .center)
                .clipped()
                .scaleEffect(pageScale, anchor: .topLeading)
                .frame(width: displayRect.width, height: displayRect.height, alignment: .topLeading)

            if isEditable && isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .allowsHitTesting(false)

                resizeHandle(.topLeft)
                resizeHandle(.topRight)
                resizeHandle(.bottomLeft)
                resizeHandle(.bottomRight)
            }
        }
        .frame(
            width: displayRect.width,
            height: displayRect.height,
            alignment: .topLeading
        )
        .position(x: displayRect.midX, y: displayRect.midY)
    }

    @ViewBuilder
    private var boxContent: some View {
        Group {
            if let mathImage {
                Image(nsImage: mathImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(box.latex.isEmpty ? (isEditable ? "Math" : "") : box.latex)
                    .font(.system(size: 12))
                    .foregroundStyle(box.latex.isEmpty ? Color.secondary : textColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isEditable { onBeginEditing() }
        }
        .onTapGesture {
            if isEditable { onSelect() }
        }
        .gesture(isEditable ? moveGesture : nil)
        .onHover { hovering in
            guard isEditable else { return }
            if hovering {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = box
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard let origin = dragOrigin else {
                    dragTranslation = .zero
                    return
                }
                let updated = movedBox(origin: origin, translation: value.translation)
                onChange(updated)
                dragOrigin = nil
                dragTranslation = .zero
            }
    }

    private func movedBox(origin: PDFMathBox, translation: CGSize) -> PDFMathBox {
        guard geometry.pageRect.width > 0, geometry.pageRect.height > 0 else {
            return origin
        }
        var updated = origin
        let dx = translation.width / geometry.pageRect.width
        let dy = translation.height / geometry.pageRect.height
        updated.x = min(max(0, origin.x + dx), max(0, 1 - updated.width))
        updated.y = min(max(0, origin.y + dy), max(0, 1 - updated.height))
        return updated
    }

    private func resizeHandle(_ corner: ResizeCorner) -> some View {
        let point: CGPoint
        switch corner {
        case .topLeft:
            point = CGPoint(x: 6, y: 6)
        case .topRight:
            point = CGPoint(x: displayRect.width - 6, y: 6)
        case .bottomLeft:
            point = CGPoint(x: 6, y: displayRect.height - 6)
        case .bottomRight:
            point = CGPoint(x: displayRect.width - 6, y: displayRect.height - 6)
        }

        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
            .frame(width: 7, height: 7)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .position(point)
            .gesture(resizeGesture(corner))
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    private func resizeGesture(_ corner: ResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if resizeOrigin == nil {
                    resizeOrigin = box
                    resizeCorner = corner
                }
                resizeTranslation = value.translation
            }
            .onEnded { value in
                guard let origin = resizeOrigin, resizeCorner == corner else {
                    resizeTranslation = .zero
                    return
                }
                let updated = resizedBox(origin: origin, translation: value.translation, corner: corner)
                onChange(updated)
                resizeOrigin = nil
                resizeTranslation = .zero
                resizeCorner = nil
            }
    }

    private func resizedBox(
        origin: PDFMathBox,
        translation: CGSize,
        corner: ResizeCorner
    ) -> PDFMathBox {
        guard geometry.pageRect.width > 0, geometry.pageRect.height > 0 else {
            return origin
        }

        let dx = translation.width / geometry.pageRect.width
        let dy = translation.height / geometry.pageRect.height
        let minWidth = 0.05
        let minHeight = 0.03

        var x = origin.x
        var y = origin.y
        var width = origin.width
        var height = origin.height

        switch corner {
        case .bottomRight:
            width = max(minWidth, origin.width + dx)
            height = max(minHeight, origin.height + dy)
        case .bottomLeft:
            x = min(max(0, origin.x + dx), origin.x + origin.width - minWidth)
            width = origin.x + origin.width - x
            height = max(minHeight, origin.height + dy)
        case .topRight:
            width = max(minWidth, origin.width + dx)
            y = min(max(0, origin.y + dy), origin.y + origin.height - minHeight)
            height = origin.y + origin.height - y
        case .topLeft:
            x = min(max(0, origin.x + dx), origin.x + origin.width - minWidth)
            width = origin.x + origin.width - x
            y = min(max(0, origin.y + dy), origin.y + origin.height - minHeight)
            height = origin.y + origin.height - y
        }

        var updated = origin
        updated.x = x
        updated.y = y
        updated.width = min(max(minWidth, width), 1 - x)
        updated.height = min(max(minHeight, height), 1 - y)
        return updated
    }
}

private struct PDFTextBoxInlineEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let color: NSColor
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let textView = PDFInlineTextView()
        textView.delegate = context.coordinator
        textView.onEscape = { [weak coordinator = context.coordinator] in
            coordinator?.commit()
        }
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = color
        textView.insertionPointColor = color
        textView.font = font
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        scrollView.documentView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.textColor = color
        textView.insertionPointColor = color
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PDFTextBoxInlineEditor

        init(_ parent: PDFTextBoxInlineEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }

        func commit() {
            parent.onCommit()
        }
    }
}

private final class PDFInlineTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

struct PDFCanvasEventMonitor: NSViewRepresentable {
    let onScroll: (CGSize) -> Void
    let onMagnify: (CGFloat) -> Void

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
        var onScroll: ((CGSize) -> Void)?
        var onMagnify: ((CGFloat) -> Void)?

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
                    view.onScroll?(
                        CGSize(
                            width: event.scrollingDeltaX,
                            height: event.scrollingDeltaY
                        )
                    )
                    return nil
                case .magnify:
                    view.onMagnify?(event.magnification)
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

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else {
            return nil
        }
        let hasAlpha = value.count == 8
        let red = (number >> (hasAlpha ? 24 : 16)) & 0xFF
        let green = (number >> (hasAlpha ? 16 : 8)) & 0xFF
        let blue = (number >> (hasAlpha ? 8 : 0)) & 0xFF
        let alpha = hasAlpha ? Double(number & 0xFF) / 255 : 1
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: alpha
        )
    }

    var hexString: String {
        guard let cgColor = self.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return "#000000"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }

    var hexStringWithAlpha: String {
        guard let cgColor = self.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return "#00000000"
        }
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)),
            Int(round(color.alphaComponent * 255))
        )
    }
}
