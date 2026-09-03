// swift-tools-version: 6.2

import Foundation
import PackageDescription

// Swift Testing ships inside the Command Line Tools as a *framework*, and on a
// machine with no Xcode SwiftPM passes its directory as a header search path
// rather than a framework search path — so `import Testing` cannot be resolved.
// Adding `-F` fixes it. The path is only added when it actually exists, so a
// machine with Xcode (and CI) is untouched.
let commandLineToolsFrameworks =
    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

// Testing.framework in turn loads lib_TestingInterop.dylib from a sibling
// directory that is likewise not on the default search path.
let commandLineToolsLibraries =
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let hasCommandLineToolsFrameworks =
    FileManager.default.fileExists(atPath: commandLineToolsFrameworks)

let testingCompileFlags: [String] =
    hasCommandLineToolsFrameworks ? ["-F", commandLineToolsFrameworks] : []

// The framework also has to be findable at run time, or the test bundle builds
// and then fails to load.
let testingLinkFlags: [String] = hasCommandLineToolsFrameworks
    ? ["-F", commandLineToolsFrameworks,
       "-Xlinker", "-rpath", "-Xlinker", commandLineToolsFrameworks,
       "-Xlinker", "-rpath", "-Xlinker", commandLineToolsLibraries]
    : []

let sharedSwiftSettings: [SwiftSetting] = [
    // Everything starts on the main actor and stays there until profiling says
    // otherwise. For an app this size that is the whole concurrency design.
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "Tray",
    platforms: [.macOS("26.0")],
    targets: [
        // The whole app. `Scripts/build.sh` takes the binary this produces and
        // assembles Tray.app around it; SwiftPM never sees the bundle.
        .executableTarget(
            name: "Tray",
            path: "Sources/Tray",
            swiftSettings: sharedSwiftSettings
        ),
        // The Control Center extension. A separate executable because an
        // appex is its own process with its own entry point; `build.sh` puts
        // the binary this produces inside the app's PlugIns directory.
        .executableTarget(
            name: "TrayControls",
            path: "Sources/TrayControls",
            swiftSettings: sharedSwiftSettings + [
                // Extensions may only use API that is safe outside a full app.
                .unsafeFlags(["-application-extension"]),
            ],
            linkerSettings: [
                // The piece Xcode supplies silently for extension targets, and
                // the reason a hand-built appex registers but never works: an
                // app extension's entry point is `NSExtensionMain`, not `main`.
                // With the default entry point the process starts, resolves its
                // widget bundle, reaches the end of `main` and exits — and the
                // host reports only "the connection was invalidated", which
                // says nothing about why.
                .unsafeFlags([
                    "-application-extension",
                    "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
                ]),
            ]
        ),
        .testTarget(
            name: "TrayTests",
            dependencies: ["Tray"],
            path: "Tests/TrayTests",
            swiftSettings: sharedSwiftSettings
                + (testingCompileFlags.isEmpty ? [] : [.unsafeFlags(testingCompileFlags)]),
            linkerSettings: testingLinkFlags.isEmpty
                ? []
                : [.unsafeFlags(testingLinkFlags)]
        ),
    ]
)
