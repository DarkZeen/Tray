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
/// A URL rather than simply opening the app, so it works the same whether Tray
/// is already running or not: LaunchServices starts the app if it has to, then
/// delivers the URL either way.
///
/// It opens Settings rather than the shelf. The shelf was the obvious first
/// choice and the wrong one — it appears at the top of the screen and closes
/// itself a moment later, so pressing a control in Control Center and watching
/// Control Center shows you nothing at all.
struct OpenTraySettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Tray Settings"
    static let description = IntentDescription("Opens Tray's settings.")

    static let settingsURL = URL(string: "tray://settings")!

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(Self.settingsURL))
    }
}
