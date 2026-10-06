import SwiftUI

struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26, weight: .light))
                Text(clipboard.paused ? "Clipboard history is paused" : "Nothing copied yet")
                    .font(.system(size: 13, weight: .medium))
                Text("Text you copy shows up here. Click an item to copy it again.")
                    .font(.system(size: 11))
                    .opacity(0.55)
            }
            .foregroundStyle(Color.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(clipboard.sorted) { entry in
                        ClipRow(entry: entry, copied: copiedID == entry.id, clipboard: clipboard) {
                            clipboard.copy(entry)
                            copiedID = entry.id
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                if copiedID == entry.id { copiedID = nil }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ClipRow: View {
    let entry: ClipboardStore.Entry
    let copied: Bool
    @ObservedObject var clipboard: ClipboardStore
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.yellow.opacity(0.85))
            }
            Text(entry.text)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.white.opacity(0.9))

            if copied {
                Text("Copied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else if hovering {
                IconButton(symbol: entry.pinned ? "pin.slash" : "pin", help: "Pin") {
                    clipboard.togglePin(entry)
                }
                IconButton(symbol: "xmark", help: "Remove") {
                    clipboard.remove(entry)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(hovering ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .magnetic(0.06, maxShift: 3, range: 30)
    }
}
