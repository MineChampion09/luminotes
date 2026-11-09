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
    @State private var isPlacingMathBox = false
    @State private var selectedBoxID: UUID?
    @State private var selectedMathBoxID: UUID?
    @State private var editingBoxID: UUID?
    @State private var currentPage = 1
    @State private var pageCount = 0
    @State private var zoom: CGFloat = 1
    @State private var isTextOptionsPresented = false
    @State private var isMathOptionsPresented = false
    @State private var mathEditStarted = false
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
                        mathBoxes: annotations.mathBoxes,
                        isEditable: true,
                        selectedBoxID: selectedBoxID,
                        selectedMathBoxID: selectedMathBoxID,
                        editingBoxID: $editingBoxID,
                        zoom: zoom,
                        topInset: 0,
                        isPlacingTextBox: isPlacingTextBox,
                        isPlacingMathBox: isPlacingMathBox,
                        onPlaceTextBox: addTextBox(at:),
                        onPlaceMathBox: addMathBox(at:),
                        onZoomChange: { newZoom in zoom = newZoom },
                        onSelect: { id in
                            if id != editingBoxID {
                                editingBoxID = nil
                            }
                            selectedBoxID = id
                            selectedMathBoxID = nil
                            isMathOptionsPresented = false
                        },
                        onChange: updateBox,
                        onSelectMath: { id in
                            editingBoxID = nil
                            selectedBoxID = nil
                            isTextOptionsPresented = false
                            selectedMathBoxID = id
                        },
                        onChangeMath: updateMathBox,
                        onBeginEditingMath: { id in
                            editingBoxID = nil
                            selectedBoxID = nil
                            isTextOptionsPresented = false
                            selectedMathBoxID = id
                            isMathOptionsPresented = true
                            mathEditStarted = false
                        }
                    )
                    .overlay(alignment: .top) {
                        if isPlacingTextBox || isPlacingMathBox {
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
                onDelete: deleteSelectedAnnotationIfPossible
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
                        selectedMathBoxID = nil
                        editingBoxID = nil
                        isMathOptionsPresented = false
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
                        selectedMathBoxID = nil
                        editingBoxID = nil
                        isMathOptionsPresented = false
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

            if selectedMathBox != nil {
                Button {
                    isMathOptionsPresented = true
                    mathEditStarted = false
                } label: {
                    Label("Math", systemImage: "function")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .contentShape(Rectangle())
                .popover(isPresented: $isMathOptionsPresented, arrowEdge: .bottom) {
                    mathOptionsPopover
                }
            }

            Button {
                isPlacingTextBox = true
                isPlacingMathBox = false
                selectedBoxID = nil
                selectedMathBoxID = nil
                editingBoxID = nil
                isMathOptionsPresented = false
            } label: {
                Label("Add Text", systemImage: "textformat")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .contentShape(Rectangle())

            Button {
                isPlacingMathBox = true
                isPlacingTextBox = false
                selectedBoxID = nil
                selectedMathBoxID = nil
                editingBoxID = nil
                isTextOptionsPresented = false
                isMathOptionsPresented = false
            } label: {
                Label("Add Math", systemImage: "function")
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
            Image(systemName: isPlacingMathBox ? "function" : "text.cursor")
                .font(.system(size: 10.5, weight: .medium))
            Text(
                isPlacingMathBox
                    ? "Click anywhere on the page to place a math box."
                    : "Click anywhere on the page to place a text box."
            )
            .font(.system(size: 11, weight: .medium))
            Button("Cancel") {
                isPlacingTextBox = false
                isPlacingMathBox = false
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

    private var selectedMathBox: PDFMathBox? {
        guard let selectedMathBoxID else { return nil }
        return annotations.mathBoxes.first(where: { $0.id == selectedMathBoxID })
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

    private var mathOptionsPopover: some View {
        Group {
            if let box = selectedMathBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Math box")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)

                    Text("LaTeX")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)

                    SourceTextEditor(
                        text: Binding(
                            get: { selectedMathBox?.latex ?? box.latex },
                            set: { setMathLatex($0) }
                        ),
                        fontSize: 13,
                        insets: NSSize(width: 8, height: 8)
                    )
                    .frame(width: 300, height: 96)
                    .background(Palette.code)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.border, lineWidth: 1)
                    )

                    Text("The formula scales to fit the box. Drag or resize the box on the page.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)

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
                                    updateSelectedMathBox { $0.colorHex = color.hexString }
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
                                    updateSelectedMathBox { $0.backgroundColorHex = color.hexStringWithAlpha }
                                }
                            ),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .frame(width: 34)
                    }

                    Divider()

                    HStack {
                        Button("Done") {
                            isMathOptionsPresented = false
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button {
                            deleteSelectedMathBox()
                            isMathOptionsPresented = false
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryText)
                    }
                }
                .padding(16)
                .frame(width: 340)
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

    private func updateSelectedMathBox(
        recordUndo shouldRecordUndo: Bool = true,
        _ update: (inout PDFMathBox) -> Void
    ) {
        guard let selectedMathBoxID,
              let index = annotations.mathBoxes.firstIndex(where: { $0.id == selectedMathBoxID }) else {
            return
        }
        var updated = annotations.mathBoxes[index]
        update(&updated)
        guard updated != annotations.mathBoxes[index] else { return }
        if shouldRecordUndo {
            recordUndo()
        }
        annotations.mathBoxes[index] = updated
    }

    private func setMathLatex(_ latex: String) {
        guard selectedMathBox != nil else { return }
        if !mathEditStarted {
            recordUndo()
            mathEditStarted = true
        }
        updateSelectedMathBox(recordUndo: false) { $0.latex = latex }
    }

    private func updateMathBox(_ updated: PDFMathBox) {
        guard let index = annotations.mathBoxes.firstIndex(where: { $0.id == updated.id }),
              annotations.mathBoxes[index] != updated else {
            return
        }
        recordUndo()
        annotations.mathBoxes[index] = updated
    }

    private func deleteSelectedMathBox() {
        guard let selectedMathBoxID else { return }
        recordUndo()
        annotations.mathBoxes.removeAll { $0.id == selectedMathBoxID }
        self.selectedMathBoxID = nil
        editingBoxID = nil
    }

    private func deleteSelectedAnnotationIfPossible() -> Bool {
        guard editingBoxID == nil else { return false }
        if selectedBoxID != nil {
            deleteSelectedBox()
            return true
        }
        if selectedMathBoxID != nil {
            deleteSelectedMathBox()
            return true
        }
        return false
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
        if let selectedMathBoxID,
           !annotations.mathBoxes.contains(where: { $0.id == selectedMathBoxID }) {
            self.selectedMathBoxID = nil
            isMathOptionsPresented = false
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
        if let selectedMathBoxID,
           !annotations.mathBoxes.contains(where: { $0.id == selectedMathBoxID }) {
            self.selectedMathBoxID = nil
            isMathOptionsPresented = false
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
        selectedMathBoxID = nil
        editingBoxID = box.id
        isPlacingTextBox = false
        isPlacingMathBox = false
        isMathOptionsPresented = false
    }

    private func addMathBox(at point: CGPoint) {
        let width = 0.3
        let height = 0.12
        let x = min(max(0, point.x), 1 - width)
        let y = min(max(0, point.y), 1 - height)
        let box = PDFMathBox(
            page: currentPage - 1,
            x: x,
            y: y,
            width: width,
            height: height,
            latex: ""
        )
        recordUndo()
        annotations.mathBoxes.append(box)
        selectedBoxID = nil
        selectedMathBoxID = box.id
        editingBoxID = nil
        isPlacingTextBox = false
        isPlacingMathBox = false
        isTextOptionsPresented = false
        mathEditStarted = false
        DispatchQueue.main.async {
            isMathOptionsPresented = true
        }
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
