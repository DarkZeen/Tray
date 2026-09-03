import AppIntents
import SwiftUI
import WidgetKit

/// Tray's Control Center entry.
///
/// A control is not part of the app — it is a widget extension bundled inside
/// it, run by the system in its own process. This target compiles to the
/// executable inside `Tray.app/Contents/PlugIns/TrayControls.appex`, which
/// `Scripts/build.sh` assembles by hand for the same reason it assembles the
/// app by hand: there is no Xcode here to do it (§61).
@main
struct TrayControls: WidgetBundle {
    var body: some Widget {
        OpenTrayControl()
    }
}

struct OpenTrayControl: ControlWidget {
    static let kind = "com.tray.app.control.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenTraySettingsIntent()) {
                Label("Tray Settings", systemImage: "gearshape")
            }
        }
        .displayName("Tray Settings")
        .description("Open Tray's settings.")
    }
}

/// What the button does.
///
/// Opens the app, which for an agent app with no windows means "show
/// Settings" — see `applicationShouldHandleReopen`.
///
/// The first attempt returned `OpenURLIntent(tray://settings)` instead. That
/// looked more precise and did not work: the press activated Tray but the URL
/// never arrived, so the app came forward and did nothing. `openAppWhenRun` is
/// the plainer mechanism and the one already verified end to end — opening the
/// app is exactly what shows Settings.
///
/// The `tray://` URLs stay, because they are useful to a script or a Shortcut
/// even though the control no longer needs them.
struct OpenTraySettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Tray Settings"
    static let description = IntentDescription("Opens Tray's settings.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
