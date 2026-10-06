import SwiftUI

/// App-wide color theme, picked from the Activity tab. Tints the heatmap and the pet.
enum Theme: String, CaseIterable, Identifiable {
    static let storageKey = "OpenNotch.theme"

    case purple, blue, teal, green, pink, orange, rainbow
    var id: String { rawValue }

    /// Base hue (0...1), or nil for rainbow.
    var baseHue: Double? {
        switch self {
        case .purple: return 0.76
        case .blue: return 0.60
        case .teal: return 0.48
        case .green: return 0.36
        case .pink: return 0.90
        case .orange: return 0.07
        case .rainbow: return nil
        }
    }

    /// Hue for a grid column. Rainbow spreads the spectrum across the columns and drifts.
    func hue(column: Int, of columns: Int, time: Double) -> Double {
        if let baseHue { return baseHue }
        let h = Double(column) / Double(max(columns, 1)) + (time * 0.03).truncatingRemainder(dividingBy: 1)
        return h.truncatingRemainder(dividingBy: 1)
    }

    /// Color for the prompt, cursor and streak text.
    var accent: Color {
        Color(hue: baseHue ?? 0.76, saturation: 0.6, brightness: 1)
    }

    var swatch: AnyShapeStyle {
        if let baseHue { return AnyShapeStyle(Color(hue: baseHue, saturation: 0.75, brightness: 0.95)) }
        return AnyShapeStyle(AngularGradient(
            colors: stride(from: 0.0, through: 1.0, by: 0.2).map { Color(hue: $0, saturation: 0.75, brightness: 1) },
            center: .center))
    }
}

/// A row of color dots; the selected one gets a ring.
struct ThemePicker: View {
    @Binding var selection: Theme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Theme.allCases) { theme in
                Button { selection = theme } label: {
                    Circle()
                        .fill(theme.swatch)
                        .frame(width: 9, height: 9)
                        .padding(2)
                        .overlay(Circle().strokeBorder(Color.white.opacity(selection == theme ? 0.85 : 0), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.rawValue.capitalized)
                .magnetic(0.25, maxShift: 3, range: 24)
            }
        }
    }
}
