import Foundation
import AppKit
import SwiftUI
import Combine

/// Drives the history panel: query state, selection, and the actions the list
/// and keyboard both dispatch into.
@MainActor
final class HistoryViewModel: ObservableObject {

    @Published var searchQuery: String = "" { didSet { scheduleReload() } }
    @Published var kindFilter: ClipKind? = nil { didSet { reload() } }
    @Published var items: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    @Published var isGridMode: Bool = false

    nonisolated let store: HistoryStore
    private var reloadWorkItem: DispatchWorkItem?
    private var observation: NotificationObservation?

    var onDismiss: (() -> Void)?
    var onPaste: ((ClipItem, Bool) -> Void)?

    init(store: HistoryStore) {
        self.store = store
        observation = NotificationObservation(
            name: HistoryStore.didChangeNotification
        ) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    var selectedItem: ClipItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    /// Debounced so that typing a query doesn't re-run FTS on every keystroke.
    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    func reload() {
        let query = searchQuery
        let kind = kindFilter
        let store = self.store
        Task.detached(priority: .userInitiated) {
            let results = store.items(matching: query, kind: kind)
            await MainActor.run {
                let previousID = self.selectedItem?.id
                self.items = results
                // Keep the selection on the same item across a refresh where we
                // can; otherwise fall back to the top of the list.
                if let previousID, let index = results.firstIndex(where: { $0.id == previousID }) {
                    self.selectedIndex = index
                } else {
                    self.selectedIndex = min(self.selectedIndex, max(0, results.count - 1))
                }
            }
        }
    }

    func prepareForShow() {
        searchQuery = ""
        kindFilter = nil
        selectedIndex = 0
        reload()
    }

    // MARK: - Keyboard actions

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    func selectIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func activateSelected(plainTextOnly: Bool = false) {
        guard let item = selectedItem else { return }
        onPaste?(item, plainTextOnly)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.setPinned(!item.pinned, itemID: item.id)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        store.delete(itemID: item.id)
    }

    // MARK: - Preview data

    // These are `nonisolated` on purpose. They are called from detached tasks
    // so that decoding a 40-megapixel screenshot or parsing a large RTF happens
    // off the main thread -- if they were actor-isolated, awaiting them would
    // hop straight back onto main and the UI would hitch on every selection.

    nonisolated func fullImage(for item: ClipItem) -> NSImage? {
        guard let data = store.fullImageData(for: item.id) else { return nil }
        return NSImage(data: data)
    }

    nonisolated func attributedText(for item: ClipItem) -> NSAttributedString? {
        guard let (uti, data) = store.richTextData(for: item.id) else { return nil }
        switch uti {
        case UTIs.rtf:
            return NSAttributedString(rtf: data, documentAttributes: nil)
        case UTIs.rtfd:
            return NSAttributedString(rtfd: data, documentAttributes: nil)
        case UTIs.html:
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        default:
            return nil
        }
    }

    nonisolated func plainText(for item: ClipItem) -> String? {
        store.plainText(for: item.id)
    }
}
