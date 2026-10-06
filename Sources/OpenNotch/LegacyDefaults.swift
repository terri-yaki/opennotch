import Foundation

/// One-time carry-over of data saved while the app was called NotchNest
/// (bundle id com.example.notchnest), so the rename doesn't wipe the shelf or heatmap.
enum LegacyDefaults {
    static func migrate() {
        let defaults = UserDefaults.standard
        let doneKey = "OpenNotch.migratedFromNotchNest"
        guard !defaults.bool(forKey: doneKey),
              let old = UserDefaults(suiteName: "com.example.notchnest") else { return }

        let keys = [("NotchNest.activity", "OpenNotch.activity"),
                    ("NotchNest.shelfPaths", "OpenNotch.shelfPaths")]
        for (oldKey, newKey) in keys where defaults.object(forKey: newKey) == nil {
            if let value = old.object(forKey: oldKey) { defaults.set(value, forKey: newKey) }
        }
        defaults.set(true, forKey: doneKey)
    }
}
