import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BlockDropDelegate: DropDelegate {
    let targetID: UUID?
    let viewModel: EditorViewModel
    @Binding var dropTarget: DropTarget?

    func dropEntered(info: DropInfo) {
        dropTarget = targetID.map(DropTarget.before) ?? .end
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if info.hasItemsConforming(to: [.fileURL, .url]) {
            return DropProposal(operation: .copy)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if let targetID, dropTarget == .before(targetID) {
            dropTarget = nil
        } else if targetID == nil, dropTarget == .end {
            dropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropTarget = nil }

        let fileProviders = info.itemProviders(for: [.fileURL, .url]).filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        if !fileProviders.isEmpty {
            loadFileURLs(from: fileProviders) { [weak viewModel] urls in
                guard let viewModel, !urls.isEmpty else { return }
                viewModel.importDroppedFiles(urls, before: targetID)
            }
            return true
        }

        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let draggedID = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                if let targetID {
                    viewModel.moveBlock(draggedID, before: targetID)
                } else {
                    viewModel.moveBlockToEnd(draggedID)
                }
            }
        }
        return true
    }

    private func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.url.identifier
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = Self.fileURL(from: item) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }
}
