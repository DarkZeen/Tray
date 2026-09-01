import AppKit
import SwiftUI

/// The settings window (§33, §55).
///
/// Standard macOS chrome, standard controls, three tabs. This is not the
/// product and should not try to be — a custom dashboard here would be a
/// second interface to learn for something the user opens twice a year.
struct SettingsView: View {
    let settings: SettingsStore
    let launchAtLogin: LaunchAtLoginService

    let onLaunchAtLoginChanged: @MainActor @Sendable (Bool) -> Void
    let onMenuBarIconChanged: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            tray.tabItem { Label("Tray", systemImage: "tray") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420)
        .scenePadding()
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.state.isEffectivelyEnabled },
                    set: { onLaunchAtLoginChanged($0) }
                ))

                // Registration fails for real, specific reasons. Say which one,
                // in words the user can act on, rather than letting the toggle
                // quietly disagree with the system (§34).
                if let explanation = launchAtLogin.state.explanation {
                    LabeledContent("") {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Toggle("Show menu bar icon", isOn: Binding(
                    get: { settings.showsMenuBarIcon },
                    set: { onMenuBarIconChanged($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tray

    private var tray: some View {
        Form {
            Section("Activation") {
                Picker("Open the tray with", selection: Binding(
                    get: { settings.activation },
                    set: { settings.activation = $0 }
                )) {
                    ForEach(SettingsStore.Activation.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Behaviour") {
                LabeledContent("Auto-collapse after") {
                    VStack(alignment: .leading, spacing: 2) {
                        Slider(
                            value: Binding(
                                get: { settings.autoCollapseDelay },
                                set: { settings.autoCollapseDelay = $0 }
                            ),
                            in: SettingsStore.collapseDelayRange
                        )
                        Text(String(format: "%.2f seconds", settings.autoCollapseDelay))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Toggle("Show file names", isOn: Binding(
                    get: { settings.showsFileNames },
                    set: { settings.showsFileNames = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var about: some View {
        VStack(spacing: 10) {
            Image(nsImage: TrayIcon.menuBarImage())
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44)
                .foregroundStyle(.secondary)

            Text("Tray")
                .font(.title2.weight(.semibold))

            Text(Self.versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // §58: the app knows about the files the user drags in, and
            // nothing else. Worth stating where someone would look for it.
            Text("Files stay where they are. Tray keeps a reference until you drag it back out, and forgets everything when it quits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 28)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}

/// Hosts `SettingsView` in an ordinary window.
///
/// The settings window is the one place Tray behaves like a normal app: it
/// activates, takes focus and appears in the window menu, because that is what
/// someone opening settings expects.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(state: AppState) {
        let view = SettingsView(
            settings: state.settings,
            launchAtLogin: state.launchAtLogin,
            onLaunchAtLoginChanged: { [weak state] in state?.setLaunchAtLogin($0) },
            onMenuBarIconChanged: { [weak state] in state?.setMenuBarIconVisible($0) }
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tray Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
