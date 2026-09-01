import Foundation
import OSLog
import ServiceManagement

/// Launch at login (§34).
///
/// `SMAppService` needs no Developer ID, but it does need three things that
/// each fail quietly if you assume them, so each one is checked and reported
/// rather than hoped for:
///
/// 1. **A stable location.** Registration cannot survive a relaunch from a
///    mounted DMG or a translocated path.
/// 2. **User approval.** `.requiresApproval` means the item exists and is
///    switched *off* in System Settings. Registering over it looks like
///    success and does nothing at the next login.
/// 3. **A stable code signature.** An ad-hoc signature changes on every build,
///    so macOS treats each rebuild as a different app and drops the item —
///    which is the entire reason `Scripts/setup-signing.sh` exists.
///
/// The user's wish and the system's state are stored separately and reconciled
/// at startup, because they genuinely diverge.
@Observable
final class LaunchAtLoginService {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but switched off by the user in System Settings.
        case requiresApproval
        /// The app is somewhere registration cannot survive.
        case unstableLocation
        case failed(String)

        var isEffectivelyEnabled: Bool { self == .enabled }
    }

    private(set) var state: State = .disabled

    private let logger = Diagnostics.logger("launch-at-login")
    private let service = SMAppService.mainApp

    // MARK: - Reading

    func refresh() {
        guard isInStableLocation else {
            state = .unstableLocation
            return
        }

        state = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// Reconciles the stored wish with what the system actually has (§34).
    ///
    /// Runs once at launch. It re-registers an item the system lost — most
    /// often because the signature changed between builds — and it *adopts* an
    /// enable the user made directly in System Settings, so the two never drift
    /// into disagreeing about what the user asked for.
    func reconcile(intent: Bool) -> Bool {
        refresh()

        switch (intent, state) {
        case (true, .disabled):
            logger.notice("Login item missing though the user asked for it; re-registering.")
            setEnabled(true)
            return intent

        case (false, .enabled):
            // The user switched it on in System Settings rather than here.
            // Their action wins; adopt it.
            logger.notice("Login item enabled outside the app; adopting.")
            return true

        default:
            return intent
        }
    }

    // MARK: - Writing

    /// Returns the state after the attempt, so a UI toggle can be corrected
    /// rather than left showing a lie.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> State {
        guard isInStableLocation else {
            state = .unstableLocation
            logger.error("Refusing to register a login item from a read-only or translocated path.")
            return state
        }

        do {
            if enabled {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            return state
        }

        refresh()
        return state
    }

    /// Opens the exact pane the user needs when approval is the blocker.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Location

    /// A read-only volume means a mounted DMG; a `AppTranslocation` path means
    /// Gatekeeper moved the app somewhere temporary. Neither survives a
    /// relaunch, so the toggle must not pretend otherwise (§34).
    private var isInStableLocation: Bool {
        let bundleURL = Bundle.main.bundleURL

        if bundleURL.path.contains("/AppTranslocation/") { return false }

        let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return !(values?.volumeIsReadOnly ?? false)
    }
}

extension LaunchAtLoginService.State {
    /// Plain words for the settings window. No error codes.
    var explanation: String? {
        switch self {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "Tray is switched off in System Settings ▸ General ▸ Login Items."
        case .unstableLocation:
            "Move Tray to your Applications folder for this to stick."
        case .failed(let message):
            message
        }
    }
}
