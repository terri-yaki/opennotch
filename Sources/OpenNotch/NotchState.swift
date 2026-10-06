import SwiftUI

@MainActor
final class NotchState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case shelf, clipboard, music, activity
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .shelf: return "tray.fill"
            case .clipboard: return "doc.on.clipboard"
            case .music: return "music.note"
            case .activity: return "square.grid.3x3.fill"
            }
        }

        var title: String {
            switch self {
            case .shelf: return "Shelf"
            case .clipboard: return "Clipboard"
            case .music: return "Now Playing"
            case .activity: return "Activity, AI usage, CPU & memory"
            }
        }
    }

    @Published var expanded = false
    @Published var pinned = false
    @Published var tab: Tab = .shelf
    @Published var dropTargeted = false

    /// Size of the physical notch (or a small pill on Macs without one).
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasNotch = true

    /// The liquid pet, shown in a wing beside the notch while collapsed.
    @Published var showPet = UserDefaults.standard.object(forKey: "OpenNotch.showPet") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPet, forKey: "OpenNotch.showPet") }
    }

    /// True for a few seconds after the charger is connected: the wings widen and the
    /// left one shows the battery filling up.
    @Published var batteryToast = false

    let pet = PetModel()
    let cursor = CursorTracker()

    /// Expanded, the panel is a half sphere hanging from the top edge: width = 2 × height.
    static let expandedSize = CGSize(width: 600, height: 300)
    /// Where content sits inside the dome, chosen so its corners stay inside the curve.
    static let contentSize = CGSize(width: 420, height: 165)
    /// Pet's spot near the bottom of the dome (panel coordinates, top-left origin).
    static let domePetRect = CGRect(x: 300 - 50, y: 206, width: 100, height: 80)

    static let wingWidth: CGFloat = 42
    static let toastWingWidth: CGFloat = 58

    /// Collapsed size: just the notch, or the notch plus a wing on each side for the pet.
    var collapsedSize: CGSize {
        guard showPet || batteryToast else { return notchSize }
        return CGSize(width: notchSize.width + 2 * wingWidth, height: max(notchSize.height, 26))
    }

    var wingWidth: CGFloat {
        batteryToast ? Self.toastWingWidth : Self.wingWidth
    }
}
