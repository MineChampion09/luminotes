import AppKit
import PDFKit
import SwiftUI

struct PDFEditorView: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var annotations = PDFAnnotationFile()
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isPlacingTextBox = false
    @State private var selectedBoxID: UUID?
    @State private var editingBoxID: UUID?
    @State private var currentPage = 1
    @State private var pageCount = 0
    @State private var zoom: CGFloat = 1
    @State private var isTextOptionsPresented = false
    @State private var undoStack: [PDFAnnotationFile] = []
    @State private var redoStack: [PDFAnnotationFile] = []
    @State private var showSaveError = false

    var body: some View {
        ZStack {
            WindowGlassBackground()

            ZStack(alignment: .top) {
                if let document {
                    PDFPageCanvas(
                        document: document,
                        pageIndex: currentPage - 1,
                        boxes: annotations.textBoxes,
                        isEditable: true,
                        selectedBoxID: selectedBoxID,
                        editingBoxID: $editingBoxID,
                        zoom: zoom,
                        topInset: 0,
                        isPlacingTextBox: isPlacingTextBox,
                        onPlaceTextBox: addTextBox(at:),
                        onZoomChange: { newZoom in zoom = newZoom },
                        onSelect: { id in
                            if id != editingBoxID {
                                editingBoxID = nil
                            }
                            selectedBoxID = id
                        },
                        onChange: updateBox
                    )
                    .overlay(alignment: .top) {
                        if isPlacingTextBox {
                            placementHint
                                .padding(.top, 72)
                        }
                    }
                } else if isLoading {
                    ProgressView("Opening PDF…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24, weight: .light))
                        Text(loadFailed ? "Could not open PDF" : "PDF not found")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                toolbarContainer
            }
        }
        .frame(width: 1000, height: 760)
        .overlay {
            PDFEditorKeyMonitor(
                onUndo: undo,
                onRedo: redo,
                onDelete: deleteSelectedBoxIfPossible
            )
            .allowsHitTesting(false)
        }
        .onAppear(perform: loadDocument)
        .alert("Could not save annotations", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Luminotes annotation file could not be written.")
        }
    }

    private var toolbarContainer: some View {
        toolbar
            .padding(.horizontal, 12)
            .frame(height: 44)
            .liquidGlassPanel(cornerRadius: 16, tint: .luminotesSidebarTint)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
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
            .help("Close without saving")

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

            if pageCount > 1 {
                HStack(spacing: 2) {
                    Button {
                        currentPage = max(1, currentPage - 1)
                        selectedBoxID = nil
                        editingBoxID = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage <= 1)

                    Text("\(currentPage) / \(pageCount)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryText)

                    Button {
                        currentPage = min(pageCount, currentPage + 1)
                        selectedBoxID = nil
                        editingBoxID = nil
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage >= pageCount)
                }
                .foregroundStyle(Palette.secondaryText)
            }

            Spacer()

            if selectedBox != nil {
                Button {
                    isTextOptionsPresented = true
                } label: {
                    Label("Text", systemImage: "character")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .contentShape(Rectangle())
                .popover(isPresented: $isTextOptionsPresented, arrowEdge: .bottom) {
                    textOptionsPopover
                }
            }

            Button {
                isPlacingTextBox = true
                selectedBoxID = nil
                editingBoxID = nil
            } label: {
                Label("Add Text", systemImage: "textformat")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .contentShape(Rectangle())

            HStack(spacing: 2) {
                Button {
                    zoom = max(0.5, zoom - 0.2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Zoom out")

                Button {
                    zoom = 1
                } label: {
                    Text("1×")
                        .font(.system(size: 9.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset zoom")

                Button {
                    zoom = min(4, zoom + 0.2)
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

            Button("Save") {
                save()
            }
            .glassButtonStyle(prominent: true)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var placementHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.cursor")
                .font(.system(size: 10.5, weight: .medium))
            Text("Click anywhere on the page to place a text box.")
                .font(.system(size: 11, weight: .medium))
            Button("Cancel") {
                isPlacingTextBox = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryText)
        }
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .liquidGlassPanel(cornerRadius: 18, tint: .luminotesSidebarTint)
    }

    private var selectedBox: PDFTextBox? {
        guard let selectedBoxID else { return nil }
        return annotations.textBoxes.first(where: { $0.id == selectedBoxID })
    }

    private let fontChoices: [(id: String, name: String)] = [
        ("system", "System"),
        ("Helvetica", "Helvetica"),
        ("Times New Roman", "Times New Roman"),
        ("Georgia", "Georgia"),
        ("Menlo", "Menlo")
    ]

    private func fontDisplayName(_ id: String) -> String {
        fontChoices.first(where: { $0.id == id })?.name ?? "System"
    }

    private var textOptionsPopover: some View {
        Group {
            if let box = selectedBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text box")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)

                    HStack {
                        Text("Font")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Menu {
                            ForEach(fontChoices, id: \.id) { choice in
                                Button(choice.name) {
                                    updateSelectedBox { $0.fontName = choice.id }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(fontDisplayName(box.fontName))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.primaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Palette.menu)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    HStack {
                        Text("Size")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { box.fontSize },
                                set: { value in
                                    updateSelectedBox { $0.fontSize = min(max(value, 6), 96) }
                                }
                            ),
                            in: 6...96,
                            step: 1
                        ) {
                            Text("\(Int(box.fontSize)) pt")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Palette.primaryText)
                                .frame(width: 46, alignment: .leading)
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Text("Text color")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { Color(hex: box.colorHex) ?? .black },
                                set: { color in
                                    updateSelectedBox { $0.colorHex = color.hexString }
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 34)
                    }

                    HStack {
                        Text("Background")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { Color(hex: box.backgroundColorHex) ?? .clear },
                                set: { color in
                                    updateSelectedBox { $0.backgroundColorHex = color.hexStringWithAlpha }
                                }
                            ),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .frame(width: 34)
                    }

                    Divider()

                    HStack {
                        Button {
                            editingBoxID = selectedBoxID
                            isTextOptionsPresented = false
                        } label: {
                            Label("Edit Text", systemImage: "pencil")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)

                        Spacer()

                        Button {
                            deleteSelectedBox()
                            isTextOptionsPresented = false
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)
                    }
                }
                .padding(16)
                .frame(width: 320)
                .background(Palette.menu)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func updateSelectedBox(_ update: (inout PDFTextBox) -> Void) {
        guard let selectedBoxID,
              let index = annotations.textBoxes.firstIndex(where: { $0.id == selectedBoxID }) else {
            return
        }
        var updated = annotations.textBoxes[index]
        update(&updated)
        guard updated != annotations.textBoxes[index] else { return }
        recordUndo()
        annotations.textBoxes[index] = updated
    }

    private func deleteSelectedBox() {
        guard let selectedBoxID else { return }
        recordUndo()
        annotations.textBoxes.removeAll { $0.id == selectedBoxID }
        self.selectedBoxID = nil
        editingBoxID = nil
    }

    private func deleteSelectedBoxIfPossible() -> Bool {
        guard editingBoxID == nil, selectedBoxID != nil else { return false }
        deleteSelectedBox()
        return true
    }

    private func recordUndo() {
        undoStack.append(annotations)
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        editingBoxID = nil
        if let selectedBoxID,
           !annotations.textBoxes.contains(where: { $0.id == selectedBoxID }) {
            self.selectedBoxID = nil
        }
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        editingBoxID = nil
        if let selectedBoxID,
           !annotations.textBoxes.contains(where: { $0.id == selectedBoxID }) {
            self.selectedBoxID = nil
        }
    }

    private func loadDocument() {
        isLoading = true
        loadFailed = false
        annotations = PDFAnnotationStore.load(for: url)

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = PDFDocument(url: url)

            DispatchQueue.main.async {
                isLoading = false
                document = loaded
                loadFailed = loaded == nil
                pageCount = loaded?.pageCount ?? 0
            }
        }
    }

    private func addTextBox(at point: CGPoint) {
        let width = 0.3
        let height = 0.1
        let x = min(max(0, point.x), 1 - width)
        let y = min(max(0, point.y), 1 - height)
        let box = PDFTextBox(
            page: currentPage - 1,
            x: x,
            y: y,
            width: width,
            height: height,
            text: ""
        )
        recordUndo()
        annotations.textBoxes.append(box)
        selectedBoxID = box.id
        editingBoxID = box.id
        isPlacingTextBox = false
    }

    private func updateBox(_ updated: PDFTextBox) {
        guard let index = annotations.textBoxes.firstIndex(where: { $0.id == updated.id }),
              annotations.textBoxes[index] != updated else {
            return
        }
        recordUndo()
        annotations.textBoxes[index] = updated
    }

    private func save() {
        NSApp.keyWindow?.makeFirstResponder(nil)

        DispatchQueue.main.async {
            do {
                try PDFAnnotationStore.save(annotations, for: url)
                dismiss()
            } catch {
                showSaveError = true
            }
        }
    }
}


private struct PDFEditorKeyMonitor: NSViewRepresentable {
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onDelete: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        var parent: PDFEditorKeyMonitor
        private var monitor: Any?

        init(parent: PDFEditorKeyMonitor) {
            self.parent = parent
        }

        func install(for view: MonitorView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak self] event in
                guard let self,
                      let view,
                      event.window == view.window else {
                    return event
                }

                let responder = NSApp.keyWindow?.firstResponder
                if responder is NSTextView || responder is NSTextField {
                    return event
                }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let key = event.charactersIgnoringModifiers?.lowercased()

                if key == "z", flags.contains(.command) {
                    if flags.contains(.shift) {
                        self.parent.onRedo()
                    } else {
                        self.parent.onUndo()
                    }
                    return nil
                }

                if (event.keyCode == 51 || event.keyCode == 117),
                   flags.intersection([.command, .control, .option]).isEmpty {
                    return self.parent.onDelete() ? nil : event
                }

                return event
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
