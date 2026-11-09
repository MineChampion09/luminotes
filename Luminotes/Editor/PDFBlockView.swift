import AppKit
import PDFKit
import SwiftUI

struct PDFBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block

    @State private var document: PDFDocument?
    @State private var fileURL: URL?
    @State private var didFail = false
    @State private var currentPage = 1
    @State private var loadToken = UUID()
    @State private var isEditing = false
    @State private var annotations = PDFAnnotationFile()

    private var title: String {
        let alias = block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alias.isEmpty { return alias }
        if let path = block.pdfPath {
            return (path as NSString).lastPathComponent
        }
        return "PDF"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)

            if let document {
                PDFPageCanvas(
                    document: document,
                    pageIndex: currentPage - 1,
                    boxes: annotations.textBoxes,
                    mathBoxes: annotations.mathBoxes,
                    editingBoxID: .constant(nil),
                    fitsHeight: 460
                )
                .frame(height: 460)
            } else {
                missingView
            }
        }
        .glassPanel(cornerRadius: 8)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear(perform: loadDocument)
        .onChange(of: block.pdfPath) { _, _ in loadDocument() }
        .onChange(of: viewModel.currentFileURL) { _, _ in loadDocument() }
        .onChange(of: block.pdfPage) { _, page in
            guard let document else { return }
            currentPage = min(max(page ?? 1, 1), max(document.pageCount, 1))
        }
        .onDisappear {
            loadToken = UUID()
            document = nil
        }
        .sheet(isPresented: $isEditing, onDismiss: loadDocument) {
            if let fileURL {
                PDFEditorView(url: fileURL, title: title)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)

            Spacer()

            if let document, document.pageCount > 1 {
                HStack(spacing: 2) {
                    Button {
                        currentPage = max(1, currentPage - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 18, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plainPointer)
                    .disabled(currentPage <= 1)

                    Text("\(currentPage) / \(document.pageCount)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryText)

                    Button {
                        currentPage = min(document.pageCount, currentPage + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 18, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plainPointer)
                    .disabled(currentPage >= document.pageCount)
                }
                .foregroundStyle(Palette.secondaryText)
            }

            if fileURL != nil {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plainPointer)
                .help("Open PDF editor")

                Button("Open") {
                    if let fileURL {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
                .buttonStyle(.plainPointer)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var missingView: some View {
        VStack(spacing: 8) {
            Image(systemName: didFail ? "exclamationmark.triangle" : "doc.text.magnifyingglass")
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(Palette.tertiaryText)

            Text(didFail ? "Could not open PDF" : "PDF not found")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            if let path = block.pdfPath {
                Text(path)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private func loadDocument() {
        let token = UUID()
        loadToken = token

        guard let url = viewModel.pdfURL(for: block) else {
            fileURL = nil
            document = nil
            didFail = false
            return
        }

        fileURL = url
        annotations = PDFAnnotationStore.load(for: url)
        document = nil
        didFail = false
        currentPage = max(block.pdfPage ?? 1, 1)

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = PDFDocument(url: url)

            DispatchQueue.main.async {
                guard loadToken == token else { return }
                document = loaded
                didFail = loaded == nil
                if let loaded {
                    currentPage = min(max(block.pdfPage ?? 1, 1), max(loaded.pageCount, 1))
                }
            }
        }
    }
}
