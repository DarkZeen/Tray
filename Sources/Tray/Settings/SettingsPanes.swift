import AppKit
import SwiftUI

/// The four pages of the settings window.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case tray
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .tray: "Tray"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// Which page opens first. Always General, unless a debug build was asked
    /// to open somewhere else.
    static var initialSelection: SettingsPane {
        guard let requested = Diagnostics.debugSettingsPane,
              let pane = SettingsPane(rawValue: requested)
        else { return .general }
        return pane
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .tray: "tray"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    let settings: SettingsStore
    let launchAtLogin: LaunchAtLoginService
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onMenuBarIconChanged: (Bool) -> Void
    let onOpenLoginItems: () -> Void

    var body: some View {
        SettingsPaneLayout(lead: "How Tray behaves when your Mac starts, and where you can reach it.") {
            SettingsCard(
                footnote: "With the icon hidden, the tray at the top of the screen still works exactly the same."
            ) {
                SettingsRow(
                    icon: "power",
                    title: "Launch at login",
                    description: "Start Tray automatically when you log in."
                ) {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.state.isEffectivelyEnabled },
                        set: { onLaunchAtLoginChanged($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Registration fails for three specific reasons, and each one
                // has something the user can actually do about it. Saying which
                // one beats a toggle that quietly disagrees with the system
                // (§34).
                if let explanation = launchAtLogin.state.explanation {
                    SettingsCallout(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: explanation,
                        actionTitle: launchAtLogin.state == .requiresApproval
                            ? "Open Login Items"
                            : nil,
                        action: launchAtLogin.state == .requiresApproval
                            ? onOpenLoginItems
                            : nil
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "menubar.arrow.up.rectangle",
                    title: "Show menu bar icon",
                    description: "The menu bar is how you reach Settings and Quit."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsMenuBarIcon },
                        set: { onMenuBarIconChanged($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Tray

struct TrayPane: View {
    let settings: SettingsStore

    var body: some View {
        SettingsPaneLayout(lead: "What opens the shelf, how long it stays, and how much it shows.") {
            SettingsCard(title: "Opening") {
                SettingsRow(
                    icon: "cursorarrow.motionlines",
                    title: "Open the tray with",
                    description: description(for: settings.activation)
                ) {
                    Picker("", selection: Binding(
                        get: { settings.activation },
                        set: { settings.activation = $0 }
                    )) {
                        ForEach(SettingsStore.Activation.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 148)
                }
            }

            SettingsCard(
                title: "Behaviour",
                footnote: "The shelf holds up to \(TrayStore.capacity) items and always empties when Tray quits."
            ) {
                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Close after",
                    description: "How long the shelf waits once the pointer leaves."
                ) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { settings.autoCollapseDelay },
                                set: { settings.autoCollapseDelay = $0 }
                            ),
                            in: SettingsStore.collapseDelayRange
                        )
                        .frame(width: 110)

                        Text(String(format: "%.2fs", settings.autoCollapseDelay))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "textformat",
                    title: "Show file names",
                    description: "Names sit under each thumbnail."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsFileNames },
                        set: { settings.showsFileNames = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    private func description(for activation: SettingsStore.Activation) -> String {
        switch activation {
        case .hover: "Only moving the pointer to the top of the screen."
        case .drag: "Only dragging files at the top of the screen."
        case .both: "Either the pointer or a drag reaching the top of the screen."
        }
    }
}

// MARK: - Privacy

/// Modelled on the transparency page every good menu bar app now has — except
/// that Tray's version is a list of permissions it does *not* want.
///
/// It is worth a page rather than a sentence: an app that lives at the top of
/// your screen and touches your files has to answer the question, and the
/// answer here is unusually short (§58).
struct PrivacyPane: View {
    var body: some View {
        SettingsPaneLayout(lead: "Tray knows about the files you drag onto it, and nothing else.") {
            SettingsCard(
                title: "Permissions",
                footnote: "The only thing Tray asks macOS for is a login item, and only if you switch that on."
            ) {
                ForEach(Array(Self.permissions.enumerated()), id: \.offset) { index, permission in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(
                        icon: permission.icon,
                        title: permission.name,
                        description: permission.note,
                        tint: .secondary
                    ) {
                        SettingsStatus(text: "Not needed", colour: .green)
                    }
                }
            }

            SettingsCard(title: "Data") {
                SettingsRow(
                    icon: "network.slash",
                    title: "Network",
                    description: "Tray opens no connections. No account, no analytics, no update check.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Never used", colour: .green)
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "internaldrive",
                    title: "What gets stored",
                    description: "Only the settings on these pages. Which files you stashed is never written down.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Settings only", colour: .secondary)
                }

                SettingsRowDivider()

                SettingsRow(
                    icon: "doc.on.doc",
                    title: "Your files",
                    description: "The shelf holds a reference. Nothing is moved, copied, renamed or deleted.",
                    tint: .secondary
                ) {
                    SettingsStatus(text: "Untouched", colour: .green)
                }
            }
        }
    }

    private struct Permission {
        let name: String
        let icon: String
        let note: String
    }

    private static let permissions: [Permission] = [
        .init(
            name: "Accessibility",
            icon: "accessibility",
            note: "Tray never reads your input or controls other windows."
        ),
        .init(
            name: "Screen Recording",
            icon: "rectangle.dashed.badge.record",
            note: "Tray never looks at what is on your screen."
        ),
        .init(
            name: "Full Disk Access",
            icon: "externaldrive",
            note: "Tray only ever sees files you drag onto it."
        ),
        .init(
            name: "Camera and Microphone",
            icon: "mic.slash",
            note: "Nothing here records anything."
        ),
    ]
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        SettingsPaneLayout(lead: "A shelf at the top of your screen. Drag files in, drag them back out.") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage ?? TrayIcon.menuBarImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tray")
                            .font(.system(size: 17, weight: .semibold))
                        Text(Self.versionString)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("MIT licensed, and open source.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(SettingsMetrics.rowHorizontalPadding)
            }

            SettingsCard(title: "Links") {
                ForEach(Array(Self.links.enumerated()), id: \.offset) { index, link in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(icon: link.icon, title: link.title, description: link.note) {
                        Button("Open") { NSWorkspace.shared.open(link.url) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private struct Link {
        let title: String
        let note: String
        let icon: String
        let url: URL
    }

    private static let repository = "https://github.com/DarkZeen/Tray"

    private static let links: [Link] = [
        .init(
            title: "Source code",
            note: "Small enough to read in an evening.",
            icon: "chevron.left.forwardslash.chevron.right",
            url: URL(string: repository)!
        ),
        .init(
            title: "What changed",
            note: "The changelog for every release.",
            icon: "list.bullet.rectangle",
            url: URL(string: "\(repository)/blob/main/CHANGELOG.md")!
        ),
        .init(
            title: "Report a problem",
            note: "Bugs, and things that felt wrong.",
            icon: "ladybug",
            url: URL(string: "\(repository)/issues")!
        ),
    ]

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}
