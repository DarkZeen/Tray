#!/usr/bin/env bash
#
# Builds Tray.app (§61, §69).
#
# SwiftPM compiles the binary; this script assembles the bundle around it by
# hand. There is no .xcodeproj and there is no xcodebuild step, so the command
# a developer runs on a laptop is the same one CI runs (§66). If it builds
# here, it builds there.
#
#   ./Scripts/build.sh                 release build, signed, into build/
#   ./Scripts/build.sh --dev           separate bundle id, coexists with a release install
#   ./Scripts/build.sh --install       also copy into /Applications and launch
#   ./Scripts/build.sh --debug         debug configuration (TRAY_DEBUG overlay available)
#   ./Scripts/build.sh --universal     add an x86_64 slice (off by default, §60)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

CONFIGURATION="release"
BUNDLE_ID="com.tray.app"
APP_NAME="Tray"
DISPLAY_NAME="Tray"
UNIVERSAL=0
INSTALL=0

# ---------------------------------------------------------------- arguments

for argument in "$@"; do
    case "$argument" in
        --dev)
            BUNDLE_ID="com.tray.app.dev"
            DISPLAY_NAME="Tray (dev)"
            ;;
        --debug)     CONFIGURATION="debug" ;;
        --universal) UNIVERSAL=1 ;;
        --install)   INSTALL=1 ;;
        -h|--help)
            sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown option '$argument'" >&2
            exit 2
            ;;
    esac
done

# -------------------------------------------------------------- environment

command -v swift >/dev/null || {
    echo "error: swift not found. Install the Xcode Command Line Tools:" >&2
    echo "         xcode-select --install" >&2
    exit 1
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ Tray $VERSION ($BUILD_NUMBER) — $CONFIGURATION, $BUNDLE_ID"

# ------------------------------------------------------------------ compile

echo "▸ Compiling"
if [[ $UNIVERSAL -eq 1 ]]; then
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
else
    swift build -c "$CONFIGURATION" --arch arm64
    swift build -c "$CONFIGURATION" --arch arm64 --product TrayControls
    BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)/$APP_NAME"
fi

[[ -f "$BINARY" ]] || { echo "error: no binary at $BINARY" >&2; exit 1; }

BIN_DIR="$(dirname "$BINARY")"
CONTROLS_BINARY="$BIN_DIR/TrayControls"

# ----------------------------------------------------------------- assemble

echo "▸ Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"

cp Resources/Info.plist "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"            "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME"                   "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME"        "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME"             "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION"      "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"            "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSUIElement true"                         "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

# ------------------------------------------------------- Control Center

# The control lives in a widget extension inside the app. Assembled by hand for
# the same reason the app is: there is no Xcode here to do it (§61).
if [[ -f "$CONTROLS_BINARY" ]]; then
    echo "▸ Adding the Control Center extension"
    APPEX="$CONTENTS/PlugIns/TrayControls.appex"
    mkdir -p "$APPEX/Contents/MacOS"

    cp "$CONTROLS_BINARY" "$APPEX/Contents/MacOS/TrayControls"
    chmod +x "$APPEX/Contents/MacOS/TrayControls"

    mkdir -p "$APPEX/Contents/Resources"
    cp Resources/TrayControls-Info.plist "$APPEX/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.controls" \
        "$APPEX/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
        "$APPEX/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" \
        "$APPEX/Contents/Info.plist"
    # ------------------------------------------------ App Intents metadata
    #
    # The control's *button* is described to the system by a metadata bundle,
    # not by the compiled code. Without it the control appears in Control
    # Center, renders correctly, and does nothing at all when pressed — with no
    # error anywhere.
    #
    # This is the one part of the build that genuinely needs Xcode:
    # `appintentsmetadataprocessor` ships in Xcode's toolchain and not in the
    # Command Line Tools. Everything else here still works without it, so a
    # clone with CLT only builds a working app — just one whose control does
    # nothing, which the warning below says out loud.
    XCODE_DEV="$(xcode-select -p 2>/dev/null)"
    [[ "$XCODE_DEV" == *Xcode.app* ]] || XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
    XCODE_TC="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain"
    METADATA_TOOL="$XCODE_TC/usr/bin/appintentsmetadataprocessor"

    if [[ -x "$METADATA_TOOL" ]]; then
        echo "▸ Building App Intents metadata"
        WORK="$(mktemp -d)"
        XCODE_SDK="$XCODE_DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        TRIPLE="arm64-apple-macos26.0"

        # Which protocol conformances to record. Without this list the compiler
        # gathers nothing and writes no const-values file at all.
        cat > "$WORK/protocols.json" <<'PROTOCOLS'
["AppIntent","AppShortcutsProvider","AppEntity","EntityQuery","AppEnum","TransientAppEntity","WidgetBundle","Widget","ControlWidget","AppIntentsPackage"]
PROTOCOLS

        # Compiled a second time, deliberately. SwiftPM has no supplementary
        # output map for const values, so `-emit-const-values` through the
        # package manifest produces nothing; driving the compiler directly is
        # the only way to get the file the processor needs. One small source
        # file, so the duplicated work is not worth avoiding.
        "$XCODE_TC/usr/bin/swiftc" -c -parse-as-library -wmo \
            -sdk "$XCODE_SDK" -target "$TRIPLE" \
            -application-extension -swift-version 6 \
            -module-name TrayControls -o "$WORK/TrayControls.o" \
            -emit-const-values-path "$WORK/TrayControls.swiftconstvalues" \
            -Xfrontend -const-gather-protocols-file -Xfrontend "$WORK/protocols.json" \
            Sources/TrayControls/*.swift

        printf '%s\n' "$ROOT"/Sources/TrayControls/*.swift > "$WORK/sources.txt"
        echo "$WORK/TrayControls.swiftconstvalues" > "$WORK/constvals.txt"

        XCODE_BUILD="$(/usr/bin/defaults read /Applications/Xcode.app/Contents/Info ProductBuildVersion 2>/dev/null || echo 17F113)"

        "$METADATA_TOOL" \
            --output "$APPEX/Contents/Resources" \
            --toolchain-dir "$XCODE_TC" \
            --module-name TrayControls \
            --sdk-root "$XCODE_SDK" \
            --xcode-version "$XCODE_BUILD" \
            --platform-family macOS \
            --deployment-target 26.0 \
            --target-triple "$TRIPLE" \
            --source-file-list "$WORK/sources.txt" \
            --swift-const-vals-list "$WORK/constvals.txt" \
            --force >/dev/null

        rm -rf "$WORK"
        [[ -d "$APPEX/Contents/Resources/Metadata.appintents" ]] \
            || echo "  warning: metadata was not produced; the control will do nothing"
    else
        cat >&2 <<'WARNING'

  warning: Xcode was not found, so the Control Center control has no App Intents
           metadata. The control will still appear and render — and pressing it
           will do nothing, silently. Install Xcode to build a working control;
           everything else in this app builds fine without it.

WARNING
    fi
else
    echo "▸ No Control Center extension built; skipping"
fi

echo "▸ Drawing the icon"
swift Scripts/make-icon.swift "$CONTENTS/Resources/$APP_NAME.icns" >/dev/null

# Extended attributes picked up from Downloads, iCloud or a File Provider
# invalidate a signature after the fact. Strip them before signing (§61).
xattr -c -r "$APP"

# -------------------------------------------------------------------- sign
#
# Three tiers, tried in order (§67). Nothing in the source tree requires a paid
# account; the difference is only how far the result travels.

ENTITLEMENTS="$ROOT/Resources/Tray.entitlements"
APPEX_ENTITLEMENTS="$ROOT/Resources/TrayControls.entitlements"
# `-v` is omitted deliberately: the local identity from setup-signing.sh is
# self-signed and therefore untrusted, so it never shows up as "valid" even
# though codesign signs with it perfectly well (§67, tier 2).
# Matched on the quoted common name only. `find-identity` appends a trust
# status such as "(CSSMERR_TP_NOT_TRUSTED)" outside the quotes, which a looser
# pattern would drag into the identity name and then fail to find.
find_identity() {
    security find-identity -p codesigning 2>/dev/null \
        | { grep "$1" || true; } | head -1 | awk -F'"' '{ print $2 }'
}

DEVELOPER_ID="${TRAY_SIGNING_IDENTITY:-$(find_identity 'Developer ID Application')}"
SELF_SIGNED="$(find_identity 'Tray Signing')"

# Nested code is signed first and the app last, so that the app's seal covers
# an extension that is already final. Signing the other way round leaves the
# outer signature describing a bundle that then changes underneath it.
NESTED=()
[[ -d "$CONTENTS/PlugIns/TrayControls.appex" ]] \
    && NESTED+=("$CONTENTS/PlugIns/TrayControls.appex")

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "▸ Signing with Developer ID: $DEVELOPER_ID"
    for nested in "${NESTED[@]}"; do
        codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$APPEX_ENTITLEMENTS" --sign "$DEVELOPER_ID" "$nested"
    done
    codesign --force --strip-disallowed-xattrs --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
elif [[ -n "$SELF_SIGNED" ]]; then
    echo "▸ Signing with the local identity: $SELF_SIGNED"
    for nested in "${NESTED[@]}"; do
        codesign --force --strip-disallowed-xattrs \
            --entitlements "$APPEX_ENTITLEMENTS" --sign "$SELF_SIGNED" "$nested"
    done
    codesign --force --strip-disallowed-xattrs \
        --entitlements "$ENTITLEMENTS" --sign "$SELF_SIGNED" "$APP"
else
    echo "▸ Signing ad-hoc"
    for nested in "${NESTED[@]}"; do
        codesign --force --strip-disallowed-xattrs \
            --entitlements "$APPEX_ENTITLEMENTS" --sign - "$nested"
    done
    codesign --force --strip-disallowed-xattrs --sign - "$APP"
    cat >&2 <<'WARNING'

  warning: this build is signed ad-hoc, so its signature changes every time you
           build it. macOS treats each rebuild as a different application, which
           means Launch at Login will not survive a rebuild and any permissions
           you grant are dropped.

           Run ./Scripts/setup-signing.sh once to create a stable local identity.

WARNING
fi

echo "▸ Verifying"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ----------------------------------------------------------------- install

if [[ $INSTALL -eq 1 ]]; then
    echo "▸ Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
fi

echo "▸ Done: $APP"
