import SwiftUI
import AppKit

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 26, weight: .light))
                Text("Drop files here")
                    .font(.system(size: 13, weight: .medium))
                Text("Drag files to the notch from anywhere. Drag them back out when you need them.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .opacity(0.55)
            }
            .foregroundStyle(Color.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.items) { item in
                        ShelfItemCell(item: item, shelf: shelf)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 48, height: 48)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 68)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(6)
        .background(hovering ? Color.white.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.7))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .help(item.url.path)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .magnetic(0.18, maxShift: 6)
    }
}
