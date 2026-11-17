#!/bin/bash
# Build architecture-specific Mac downloads using Xcode and macOS system tools.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/package-macos.sh preview|release [output-directory]

preview   Build ad-hoc local testing images for Apple silicon and Intel.
release   Sign with Developer ID, submit both images to Apple for notarization,
          staple and validate them, and generate SHA256SUMS. Requires these
          environment variables:
            DEVELOPER_ID_APPLICATION  Full Developer ID Application certificate name
            NOTARYTOOL_PROFILE        An existing notarytool Keychain profile name

Output defaults to build/distribution/macos. Each run creates its own directory.
Verify the downloads by running "shasum -a 256 -c SHA256SUMS" in that directory.
USAGE
}

case "${1:-}" in
    preview|release) mode=$1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 2 ]]; then usage >&2; exit 2; fi

repo=$(cd "$(dirname "$0")/.." && pwd)
output=${2:-"$repo/build/distribution/macos"}
identity=-
if [[ $mode == release ]]; then
    : "${DEVELOPER_ID_APPLICATION:?Set the full Developer ID Application certificate name}"
    : "${NOTARYTOOL_PROFILE:?Set the notarytool Keychain profile name}"
    identity=$DEVELOPER_ID_APPLICATION
    if [[ $identity != "Developer ID Application: "* ]]; then
        echo "Direct-download releases require a Developer ID Application identity." >&2
        exit 1
    fi
    matches=$(security find-identity -v -p codesigning |
        awk -F'"' -v name="$identity" '$2 == name { n++ } END { print n+0 }')
    if [[ $matches != 1 ]]; then
        echo "Choose an unambiguous, valid Developer ID Application identity in your Keychain." >&2
        exit 1
    fi
fi

mkdir -p "$output"
output=$(cd "$output" && pwd)
package=$(mktemp -d "$output/.package.XXXXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/relaypad-macos.XXXXXXXX")
mounted=
cleanup() {
    if [[ -n $mounted ]]; then hdiutil detach "$mounted" -quiet || return; fi
    rm -rf "$work" "$package"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app_name='Relaypad for Mac.app'
hash_files=()
for arch in arm64 x86_64; do
    echo "Building $arch for $mode"
    derived="$work/build-$arch"
    xcodebuild -quiet -project "$repo/Relaypad.xcodeproj" -scheme 'Relaypad for Mac' \
        -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
        ARCHS="$arch" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build

    stage="$work/image-$arch"
    mkdir -p "$stage"
    app="$stage/$app_name"
    ditto "$derived/Build/Products/Release/$app_name" "$app"
    info="$app/Contents/Info.plist"
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$info")
    build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$info")
    executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$info")
    if [[ $(lipo -archs "$app/Contents/MacOS/$executable") != "$arch" ]]; then
        echo "Unexpected executable architecture for $arch." >&2
        exit 1
    fi

    label="Relaypad-$version-macOS-$arch"
    volume="Relaypad for Mac"
    if [[ $mode == release ]]; then
        codesign --force --options runtime --timestamp --sign "$identity" "$app"
    else
        codesign --force --options runtime --timestamp=none --sign - "$app"
        label="$label-local-preview"
        volume="Relaypad local preview"
        echo 'Local test build with an ad-hoc signature. Public downloads require a Developer ID signature and Apple notarization.' > "$stage/LOCAL PREVIEW.txt"
    fi
    codesign --verify --deep --strict "$app"
    ln -s /Applications "$stage/Applications"
    image="$package/$label.dmg"
    hdiutil create -quiet -fs HFS+ -format UDZO -volname "$volume" -srcfolder "$stage" "$image"

    if [[ $mode == release ]]; then
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$info")
        codesign --force --timestamp --sign "$identity" --identifier "$bundle_id.dmg.$arch" "$image"
        receipt="$work/notary-$arch.plist"
        if ! xcrun notarytool submit "$image" --keychain-profile "$NOTARYTOOL_PROFILE" \
            --wait --output-format plist > "$receipt"; then
            submission=$(plutil -extract id raw "$receipt" 2>/dev/null || true)
            echo "Notarization failed for $arch. Check notarytool history or log ${submission:-for the submission}." >&2
            exit 1
        fi
        status=$(plutil -extract status raw "$receipt")
        submission=$(plutil -extract id raw "$receipt")
        echo "Apple notarization $submission for $arch: $status"
        if [[ $status != Accepted ]]; then
            echo "Inspect the submission with xcrun notarytool log $submission." >&2
            exit 1
        fi
        xcrun stapler staple "$image"
        xcrun stapler validate "$image"
        codesign --verify --strict "$image"
        spctl --assess --type open --context context:primary-signature "$image"
    fi

    hdiutil verify -quiet "$image"
    mountpoint="$work/mounted-$arch"
    mkdir "$mountpoint"
    hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$image"
    mounted=$mountpoint
    mounted_app="$mountpoint/$app_name"
    codesign --verify --deep --strict "$mounted_app"
    [[ $(readlink "$mountpoint/Applications") == /Applications ]]
    [[ $(lipo -archs "$mounted_app/Contents/MacOS/$executable") == "$arch" ]]
    if [[ $mode == release ]]; then spctl --assess --type execute "$mounted_app"; fi
    hdiutil detach -quiet "$mountpoint"
    mounted=
    hash_files+=("$label.dmg")
done

(cd "$package" && shasum -a 256 "${hash_files[@]}" > SHA256SUMS && shasum -a 256 -c SHA256SUMS)
# Publish both verified images and their matching checksums to disk together.
# A unique run suffix preserves earlier releases and permits concurrent builds.
run_id=${package##*.}
final="$output/Relaypad-$version-build$build-$mode-$run_id"
mv "$package" "$final"
echo "Packages and SHA256SUMS: $final"
