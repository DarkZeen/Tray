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
            ControlWidgetButton(action: OpenTrayIntent()) {
                Label("Open Tray", systemImage: "tray")
            }
        }
        .displayName("Open Tray")
        .description("Show the shelf at the top of the screen.")
    }
}

/// What the button does.
///
/// It opens a URL rather than simply opening the app. Tray has no Dock tile, so
/// being *opened* already means something else — "show Settings" — and a
/// control called Open Tray has to be able to say which of the two it meant.
struct OpenTrayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Tray"
    static let description = IntentDescription("Shows the tray at the top of the screen.")

    static let trayURL = URL(string: "tray://open")!

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(Self.trayURL))
    }
}
