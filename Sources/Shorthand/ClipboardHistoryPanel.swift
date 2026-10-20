import AppKit
import ImageIO
import ShorthandCore
import SwiftUI

enum ClipboardChoice {
    case paste(ClipboardEntry)
    case copy(ClipboardEntry)
    case saveAsPrompt(String)
}

/// The Raycast-style clipboard history that ⌥⌘V opens. Deleting happens in place;
/// everything else calls back once with the choice, or nil when dismissed.
@MainActor
final class ClipboardHistoryPanel: FloatingPanel, NSWindowDelegate {
    private static var current: ClipboardHistoryPanel?
    private var completion: ((ClipboardChoice?) -> Void)?

    static func present(_ store: ClipboardHistoryStore, completion: @escaping (ClipboardChoice?) -> Void) {
        current?.finish(with: nil)

        var finish: (ClipboardChoice?) -> Void = { _ in }
        let panel = ClipboardHistoryPanel(rootView: ClipboardHistoryView(store: store, onFinish: { finish($0) }))
        finish = { [weak panel] in panel?.finish(with: $0) }
        panel.delegate = panel
        panel.completion = completion
        current = panel
        panel.show()
    }

    private func finish(with choice: ClipboardChoice?) {
        guard let completion else { return }
        self.completion = nil
        if Self.current === self { Self.current = nil }
        close()
        completion(choice)
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(with: nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }
}

private struct ClipboardHistoryView: View {
    let store: ClipboardHistoryStore
    let onFinish: (ClipboardChoice?) -> Void

    @State private var query = ""
    @State private var selectedID: ClipboardEntry.ID?
    @FocusState private var isSearchFocused: Bool

    private var results: [ClipboardEntry] { store.history.search(query) }

    private var current: ClipboardEntry? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let current {
                HStack(spacing: 0) {
                    list
                        .frame(width: 320)
                    Divider()
                    ClipboardPreview(entry: current, imageURL: current.image.map(store.imageURL(for:)))
                }
            } else {
                emptyState
            }
            ActionBar(
                status: "Clipboard History",
                actions: current.map(actions(for:)) ?? []
            )
        }
        .frame(width: 760, height: 460)
        .onAppear { isSearchFocused = true }
    }

    private func actions(for entry: ClipboardEntry) -> [ActionBar.Action] {
        var actions: [ActionBar.Action] = [
            .init(title: "Paste", keys: ["↵"]) { onFinish(.paste(entry)) },
            .init(title: "Copy", keys: ["⌘", "C"], shortcut: KeyboardShortcut("c")) { onFinish(.copy(entry)) },
        ]
        // A prompt is text, so images can't become one.
        if entry.image == nil {
            actions.append(.init(title: "Save as Prompt", keys: ["⌘", "S"], shortcut: KeyboardShortcut("s")) {
                onFinish(.saveAsPrompt(entry.text))
            })
        }
        actions.append(.init(title: "Delete", keys: ["⌘", "⌫"], shortcut: KeyboardShortcut(.delete)) { delete(entry) })
        return actions
    }

    private var searchField: some View {
        TextField("Search clipboard history…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($isSearchFocused)
            .onSubmit {
                if let current { onFinish(.paste(current)) }
            }
            .onKeyPress(.upArrow) { move(by: -1); return .handled }
            .onKeyPress(.downArrow) { move(by: 1); return .handled }
            .onKeyPress(.escape) { onFinish(nil); return .handled }
            .padding(.horizontal, 18)
            .frame(height: 56)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(section.entries) { entry in
                            ClipboardRow(entry: entry, imageURL: entry.image.map(store.imageURL(for:)), isSelected: entry.id == current?.id)
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { onFinish(.paste(entry)) }
                                .onTapGesture { selectedID = entry.id }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    /// Today, Yesterday, then Earlier. Entries are newest first, so the display
    /// order matches `results` and the arrow keys.
    private var sections: [(title: String, entries: [ClipboardEntry])] {
        let calendar = Calendar.current
        var today: [ClipboardEntry] = [], yesterday: [ClipboardEntry] = [], earlier: [ClipboardEntry] = []
        for entry in results {
            if calendar.isDateInToday(entry.date) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.date) {
                yesterday.append(entry)
            } else {
                earlier.append(entry)
            }
        }
        return [("Today", today), ("Yesterday", yesterday), ("Earlier", earlier)].filter { !$0.1.isEmpty }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.history.entries.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            if !store.history.entries.isEmpty {
                Text("No results")
                    .font(.system(size: 14, weight: .medium))
            } else if store.isRecording {
                Text("Nothing copied yet")
                    .font(.system(size: 14, weight: .medium))
                Text("Text and images you copy show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Clipboard history is off")
                    .font(.system(size: 14, weight: .medium))
                Text("Turn on Record Clipboard History in the menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(by offset: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == current?.id } ?? 0
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }

    /// Removes it and selects the next one down, like deleting in a list.
    private func delete(_ entry: ClipboardEntry) {
        let results = results
        if let index = results.firstIndex(where: { $0.id == entry.id }) {
            let next = results.indices.contains(index + 1) ? results[index + 1] : (index > 0 ? results[index - 1] : nil)
            selectedID = next?.id
        }
        store.delete(id: entry.id)
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let imageURL: URL?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let imageURL, let thumbnail = ImageLoader.image(at: imageURL, maxPixels: 64) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            } else {
                SourceAppIcon(bundleID: entry.sourceBundleID)
            }
            Text(entry.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(shortAge(entry.date))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            isSelected ? Color.primary.opacity(0.1) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    /// "now", "5m", "3h", "2d".
    private func shortAge(_ date: Date) -> String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}

/// The icon of the app something was copied from, or a plain clipboard.
private struct SourceAppIcon: View {
    let bundleID: String?

    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let image = Self.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

/// Downscaled images for thumbnails and the preview, decoded once and kept.
@MainActor
private enum ImageLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(at url: URL, maxPixels: Int) -> NSImage? {
        let key = "\(url.path)#\(maxPixels)"
        if let cached = cache[key] { return cached }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache[key] = image
        return image
    }
}

private struct ClipboardPreview: View {
    let entry: ClipboardEntry
    let imageURL: URL?

    /// Very long copies are cut short in the preview so it stays quick; pasting uses all of it.
    private var previewText: String {
        entry.text.count > 5000 ? String(entry.text.prefix(5000)) + "\n…" : entry.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL {
                Group {
                    if let image = ImageLoader.image(at: imageURL, maxPixels: 1200) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    } else {
                        Text("The image file is missing.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                ScrollView {
                    Text(previewText)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
            }
            Divider()
            VStack(spacing: 8) {
                detail("Copied from", entry.sourceName ?? "Unknown")
                detail("Copied", entry.date.formatted(date: .abbreviated, time: .shortened))
                detail("Size", size)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var size: String {
        if let image = entry.image {
            return "\(image.width)×\(image.height), " + image.byteCount.formatted(.byteCount(style: .file))
        }
        let characters = entry.text.count
        let lines = entry.text.split(whereSeparator: \.isNewline).count
        return "\(characters) characters" + (lines > 1 ? ", \(lines) lines" : "")
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12))
    }
}
