import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(viewModel: viewModel)
            Divider()
            HStack(spacing: 0) {
                Group {
                    if viewModel.items.isEmpty {
                        EmptyStateView(hasQuery: !viewModel.searchQuery.isEmpty)
                    } else if viewModel.isGridMode {
                        ItemGrid(viewModel: viewModel)
                    } else {
                        ItemList(viewModel: viewModel)
                    }
                }
                .frame(width: 320)

                Divider()

                PreviewPane(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            FooterBar(viewModel: viewModel)
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(.regularMaterial)
    }
}

// MARK: - Search

private struct SearchBar: View {
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search clipboard history", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit { viewModel.activateSelected() }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            KindFilterMenu(viewModel: viewModel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { isSearchFocused = true }
    }
}

private struct KindFilterMenu: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        Menu {
            Button("All Types") { viewModel.kindFilter = nil }
            Divider()
            ForEach(ClipKind.allCases, id: \.self) { kind in
                Button {
                    viewModel.kindFilter = kind
                } label: {
                    Label(kind.displayName, systemImage: kind.symbolName)
                }
            }
        } label: {
            Image(systemName: viewModel.kindFilter?.symbolName ?? "line.3.horizontal.decrease.circle")
                .foregroundStyle(viewModel.kindFilter == nil ? .secondary : .blue)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - List

private struct ItemList: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        ItemRowView(
                            item: item,
                            index: index,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            viewModel.selectIndex(index)
                            viewModel.activateSelected()
                        }
                        .onTapGesture { viewModel.selectIndex(index) }
                        .contextMenu { ItemContextMenu(viewModel: viewModel, index: index, item: item) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                guard viewModel.items.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

private struct ItemGrid: View {
    @ObservedObject var viewModel: HistoryViewModel

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        GridTile(item: item, isSelected: index == viewModel.selectedIndex)
                            .id(item.id)
                            .onTapGesture(count: 2) {
                                viewModel.selectIndex(index)
                                viewModel.activateSelected()
                            }
                            .onTapGesture { viewModel.selectIndex(index) }
                            .contextMenu { ItemContextMenu(viewModel: viewModel, index: index, item: item) }
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                guard viewModel.items.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

private struct GridTile: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))

            if let path = item.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: item.kind.symbolName).font(.title3)
                    Text(item.previewText)
                        .font(.system(size: 9))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                .padding(4)
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .padding(3)
                    .background(.thinMaterial, in: Circle())
                    .padding(3)
            }
        }
    }
}

private struct ItemContextMenu: View {
    @ObservedObject var viewModel: HistoryViewModel
    let index: Int
    let item: ClipItem

    var body: some View {
        Button("Paste") {
            viewModel.selectIndex(index)
            viewModel.activateSelected()
        }
        Button("Paste as Plain Text") {
            viewModel.selectIndex(index)
            viewModel.activateSelected(plainTextOnly: true)
        }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") {
            viewModel.selectIndex(index)
            viewModel.togglePinSelected()
        }
        Button("Delete", role: .destructive) {
            viewModel.selectIndex(index)
            viewModel.deleteSelected()
        }
    }
}

// MARK: - Chrome

private struct EmptyStateView: View {
    let hasQuery: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasQuery ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(hasQuery ? "No matches" : "Nothing copied yet")
                .foregroundStyle(.secondary)
            if !hasQuery {
                Text("Copy something and it will show up here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FooterBar: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "\u{2191}\u{2193}", label: "Navigate")
            KeyHint(keys: "\u{21A9}", label: "Paste")
            KeyHint(keys: "\u{2325}\u{21A9}", label: "Plain")
            KeyHint(keys: "\u{2318}P", label: "Pin")
            KeyHint(keys: "\u{21E5}", label: viewModel.isGridMode ? "List" : "Grid")
            Spacer()
            Text("\(viewModel.items.count) items")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
