import AppKit
import SwiftUI

/// Owns the notch panel: positions it, expands/collapses it, and watches the
/// mouse (hover and file drags) to decide when to do so.
@MainActor
final class NotchController {
    let state = NotchState()

    private let shelf: ShelfStore
    private let clipboard: ClipboardStore
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var notchCenterX: CGFloat = 0

    init(shelf: ShelfStore, clipboard: ClipboardStore) {
        self.shelf = shelf
        self.clipboard = clipboard
    }

    // MARK: Lifecycle

    func start() {
        refreshGeometry()

        let root = NotchRootView(state: state, shelf: shelf, clipboard: clipboard)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []   // don't let SwiftUI's content size drive the window size

        let panel = NotchPanel()
        panel.contentView = host
        // The panel always has the expanded size; the SwiftUI shape does all the morphing.
        // While collapsed it's transparent outside the tab and lets clicks through.
        panel.setFrame(frame(expanded: true), display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel

        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenChanged() }
        }
    }

    // MARK: Geometry

    private var targetScreen: NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func refreshGeometry() {
        let screen = targetScreen
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            state.notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            state.hasNotch = true
            notchCenterX = left.maxX + width / 2
        } else {
            state.notchSize = CGSize(width: 160, height: 10)
            state.hasNotch = false
            notchCenterX = screen.frame.midX
        }
        updatePetAnchor()
    }

    /// Where the pet is on screen, so it can look at the cursor.
    private func updatePetAnchor() {
        let top = targetScreen.frame.maxY
        if state.expanded {
            let spot = NotchState.domePetRect
            let left = notchCenterX - NotchState.expandedSize.width / 2
            state.pet.anchor = CGPoint(x: left + spot.midX, y: top - spot.midY)
        } else {
            let x = notchCenterX + state.notchSize.width / 2 + state.wingWidth / 2
            state.pet.anchor = CGPoint(x: x, y: top - state.collapsedSize.height / 2)
        }
    }

    private func frame(expanded: Bool) -> NSRect {
        let screen = targetScreen
        let size = expanded ? NotchState.expandedSize : state.collapsedSize
        return NSRect(
            x: notchCenterX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Region of the screen that triggers expansion while collapsed.
    private var hoverRect: NSRect {
        frame(expanded: false).insetBy(dx: -28, dy: -6).offsetBy(dx: 0, dy: -2)
    }

    private func screenChanged() {
        refreshGeometry()
        panel?.setFrame(frame(expanded: true), display: true)
    }

    // MARK: Expand / collapse

    func setExpanded(_ expanded: Bool) {
        guard state.expanded != expanded else { return }
        if expanded {
            shelf.prune()
            panel?.ignoresMouseEvents = false
            withAnimation(.spring(duration: 0.42, bounce: 0)) { state.expanded = true }
        } else {
            state.cursor.location = nil
            withAnimation(.spring(duration: 0.34, bounce: 0)) { state.expanded = false }
            panel?.ignoresMouseEvents = true
        }
        updatePetAnchor()
    }

    func setShowPet(_ show: Bool) {
        state.showPet = show
        updatePetAnchor()
    }

    func setPinned(_ pinned: Bool) {
        state.pinned = pinned
        if pinned { setExpanded(true) }
    }

    // MARK: Mouse tracking

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseChanged() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.mouseChanged() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private var dragPasteboardHasFiles: Bool {
        NSPasteboard(name: .drag).canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func mouseChanged() {
        let point = NSEvent.mouseLocation
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0

        state.pet.cursorMoved(to: point)
        state.pet.happy = !state.expanded && hoverRect.contains(point)

        if state.expanded {
            // Panel-local, top-left origin, for the magnetic controls and the dome's light.
            let f = frame(expanded: true)
            state.cursor.location = CGPoint(x: point.x - f.minX, y: f.maxY - point.y)

            // Stay open while the cursor is within the dome (plus a small margin).
            let domeRadius = NotchState.expandedSize.height
            let inDome = hypot(point.x - f.midX, point.y - f.maxY) < domeRadius + 14 && point.y <= f.maxY + 2
            if inDome || state.pinned {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if hoverRect.contains(point) {
            if buttonDown {
                if dragPasteboardHasFiles { setExpanded(true) }
            } else {
                scheduleExpand()
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
        }
    }

    private func scheduleExpand() {
        guard hoverTask == nil else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            if self.hoverRect.contains(NSEvent.mouseLocation) { self.setExpanded(true) }
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            // Never collapse mid-drag (e.g. while dragging a file out of the shelf).
            if NSEvent.pressedMouseButtons == 0, !self.state.pinned {
                self.setExpanded(false)
            }
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}
