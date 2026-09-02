import Foundation
import Observation

/// How the tray should behave (§33).
///
/// Deliberately short. Every option here changes something the user can point
/// at in the tray itself; there is no settings screen full of knobs for
/// preferences nobody has.
@Observable
final class SettingsStore {
    /// What is allowed to open the tray (§12, §13).
    enum Activation: String, CaseIterable, Sendable {
        case hover
        case drag
        case both

        var title: String {
            switch self {
            case .hover: "Hover"
            case .drag: "Drag files to top"
            case .both: "Both"
            }
        }

        var allowsHover: Bool { self != .drag }
        var allowsDrag: Bool { self != .hover }
    }

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let activation = "activation"
        static let autoCollapseDelay = "autoCollapseDelay"
        static let showsFileNames = "showsFileNames"
    }

    private let defaults: UserDefaults

    /// The user's *wish* about launching at login, stored separately from what
    /// the system actually has registered. §34 is emphatic about this: the two
    /// drift apart for real reasons — a build with a different signature, an
    /// approval revoked in System Settings — and reconciling them at startup is
    /// only possible if both are recorded.
    ///
    /// Optional, because "never asked" is a genuinely different state from
    /// "asked for off", and conflating them is not harmless: on a fresh install
    /// `SMAppService` can report the app as already enabled, and a `Bool` would
    /// make startup reconciliation write that down as a preference the user
    /// never expressed.
    var launchAtLoginIntent: Bool? {
        didSet {
            if let launchAtLoginIntent {
                defaults.set(launchAtLoginIntent, forKey: Key.launchAtLogin)
            } else {
                defaults.removeObject(forKey: Key.launchAtLogin)
            }
        }
    }

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    var activation: Activation {
        didSet { defaults.set(activation.rawValue, forKey: Key.activation) }
    }

    /// Seconds the tray waits after the pointer leaves before closing (§17).
    var autoCollapseDelay: Double {
        didSet { defaults.set(autoCollapseDelay, forKey: Key.autoCollapseDelay) }
    }

    var showsFileNames: Bool {
        didSet { defaults.set(showsFileNames, forKey: Key.showsFileNames) }
    }

    static let collapseDelayRange: ClosedRange<Double> = 0.2...3.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.showsMenuBarIcon: true,
            Key.showsFileNames: true,
            Key.activation: Activation.both.rawValue,
            Key.autoCollapseDelay: TrayAnimation.collapseDelay,
        ])

        // `object(forKey:)` rather than `bool(forKey:)`, so an absent key
        // stays absent instead of arriving as `false`.
        launchAtLoginIntent = defaults.object(forKey: Key.launchAtLogin) as? Bool
        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        showsFileNames = defaults.bool(forKey: Key.showsFileNames)
        autoCollapseDelay = defaults.double(forKey: Key.autoCollapseDelay)
        activation = Activation(rawValue: defaults.string(forKey: Key.activation) ?? "")
            ?? .both

        Diagnostics.logger("settings").debug(
            """
            loaded: collapse=\(self.autoCollapseDelay, privacy: .public) \
            names=\(self.showsFileNames, privacy: .public) \
            icon=\(self.showsMenuBarIcon, privacy: .public) \
            launchIntent=\(self.launchAtLoginIntent.map(String.init(describing:)) ?? "unset", privacy: .public)
            """
        )
    }
}
