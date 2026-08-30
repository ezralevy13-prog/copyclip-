import SwiftUI
import AppKit

// MARK: - Toolbar

/// The classic macOS preferences toolbar: icon above label, selected item
/// carrying a rounded highlight.
struct SettingsToolbar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 20, weight: .regular))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 74)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selection == tab
                                  ? Color(nsColor: .quaternaryLabelColor).opacity(0.6)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

enum SettingsTab: CaseIterable {
    case general
    case ignoredApps
    case clipsManagement
    case about

    var title: String {
        switch self {
        case .general:         return "General"
        case .ignoredApps:     return "Ignored Apps"
        case .clipsManagement: return "Clips Management"
        case .about:           return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general:         return "gearshape"
        case .ignoredApps:     return "eye.slash"
        case .clipsManagement: return "list.clipboard"
        case .about:           return "info.circle"
        }
    }
}

// MARK: - Section

/// A titled group box, matching the grouped look of macOS settings panes.
struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 11) {
                content
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}

// MARK: - Number field

/// A numeric field that commits on Return *and* on losing focus, then shows
/// back the clamped value.
///
/// Committing on every keystroke is wrong here: typing "80" would momentarily
/// read as 8 and get clamped up to the minimum before the second digit
/// arrived. Committing only on Return is also wrong -- clicking away silently
/// discarded the edit.
struct SettingsNumberField: View {
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            .focused($isFocused)
            .onAppear { text = String(value) }
            .onSubmit { commit() }
            .onChange(of: isFocused) { focused in
                if !focused { commit() }
            }
            .onChange(of: value) { newValue in
                // Reflect changes made elsewhere (e.g. a cap lowered on
                // another tab) while this field isn't being edited.
                if !isFocused { text = String(newValue) }
            }
    }

    private func commit() {
        let parsed = Int(text.trimmingCharacters(in: .whitespaces)) ?? value
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        text = String(clamped)
        onCommit(clamped)
    }
}

/// Label, field and trailing unit, aligned in a column.
struct SettingsNumberRow: View {
    let label: String
    let unit: String
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 92, alignment: .trailing)
            SettingsNumberField(value: value, range: range, onCommit: onCommit)
            Text(unit)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Explanatory text under a control.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
