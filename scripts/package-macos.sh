#!/bin/bash
# Build architecture-specific Mac downloads using Xcode and macOS system tools.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/package-macos.sh preview|release [output-directory]
       scripts/package-macos.sh notarized-apps arm64-input intel-input [output-directory]

preview   Build ad-hoc local testing images for Apple silicon and Intel.
release   Sign with Developer ID, submit both images to Apple for notarization,
          staple and validate them, and generate SHA256SUMS. Requires these
          environment variables:
            DEVELOPER_ID_APPLICATION  Full Developer ID Application certificate name
            NOTARYTOOL_PROFILE        An existing notarytool Keychain profile name

notarized-apps   Each input can be an already-submitted .xcarchive or its exported,
          stapled .app. Archives are retrieved using xcodebuild -exportNotarizedApp.
          If Apple is still processing, rerun this command after issuance.
          This mode validates the individual apps in unsigned drag-install DMGs,
          checks their installed copies under quarantine, and has no upload step.

Output defaults to build/distribution/macos. Each run creates its own directory.
Verify the downloads by running "shasum -a 256 -c SHA256SUMS" in that directory.
USAGE
}

repo=$(cd "$(dirname "$0")/.." && pwd)
default_output="$repo/build/distribution/macos"
mode=${1:-}
case "$mode" in
    preview|release)
        if [[ $# -gt 2 ]]; then usage >&2; exit 2; fi
        output=${2:-"$default_output"}
        ;;
    notarized-apps)
        if [[ $# -lt 3 || $# -gt 4 ]]; then usage >&2; exit 2; fi
        arm_app=$2
        intel_app=$3
        output=${4:-"$default_output"}
        ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

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

verify_stapled_app() {
    local path=$1
    codesign --verify --strict --deep --test-requirement='=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$path"
    xcrun stapler validate "$path"
    spctl --assess --type execute --verbose=2 --ignore-cache --no-cache "$path"
    syspolicy_check distribution "$path"
}

app_name='Relaypad for Mac.app'
first_release=''
hash_files=()
for arch in arm64 x86_64; do
    echo "Packaging $arch for $mode"
    if [[ $mode == notarized-apps ]]; then
        if [[ $arch == arm64 ]]; then source_app=$arm_app; else source_app=$intel_app; fi
        source_app=${source_app%/}
        if [[ $source_app == *.xcarchive ]]; then
            export_dir="$work/export-$arch"
            xcodebuild -exportNotarizedApp -archivePath "$source_app" -exportPath "$export_dir"
            source_app="$export_dir/$app_name"
        fi
    else
        derived="$work/build-$arch"
        xcodebuild -quiet -project "$repo/Relaypad.xcodeproj" -scheme 'Relaypad for Mac' \
            -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
            ARCHS="$arch" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
        source_app="$derived/Build/Products/Release/$app_name"
    fi
    stage="$work/image-$arch"
    mkdir -p "$stage"
    app="$stage/$app_name"
    ditto "$source_app" "$app"
    info="$app/Contents/Info.plist"
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$info")
    build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$info")
    executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$info")
    if [[ $executable != 'Relaypad for Mac' || ! $version =~ ^[[:alnum:]][[:alnum:]._-]*$ || ! $build =~ ^[[:alnum:]][[:alnum:]._-]*$ ]]; then
        echo "Unexpected app executable, version, or build number in $info." >&2
        exit 1
    fi
    if [[ $(lipo -archs "$app/Contents/MacOS/$executable") != "$arch" ]]; then
        echo "Unexpected executable architecture for $arch." >&2
        exit 1
    fi

    label="Relaypad-$version-macOS-$arch"
    volume="Relaypad for Mac"
    if [[ $mode == release ]]; then
        codesign --force --options runtime --timestamp --sign "$identity" "$app"
    elif [[ $mode == notarized-apps ]]; then
        verify_stapled_app "$app"
        team=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
        bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$info")
        release_id="$team/$bundle_id/$version/$build"
        if [[ -n $first_release && $release_id != "$first_release" ]]; then
            echo "The two signed exports must be from the same team, bundle, version and build." >&2
            exit 1
        fi
        first_release=$release_id
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
    test_image=$image
    if [[ $mode == notarized-apps ]]; then
        # Model a fresh browser download while keeping the publishable files untouched.
        test_image="$work/download-$arch.dmg"
        cp "$image" "$test_image"
        quarantine="0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)"
        xattr -w com.apple.quarantine "$quarantine" "$test_image"
    fi
    hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$test_image"
    mounted=$mountpoint
    mounted_app="$mountpoint/$app_name"
    codesign --verify --deep --strict "$mounted_app"
    [[ $(readlink "$mountpoint/Applications") == /Applications ]]
    [[ $(lipo -archs "$mounted_app/Contents/MacOS/$executable") == "$arch" ]]
    if [[ $mode == release ]]; then
        spctl --assess --type execute "$mounted_app"
    elif [[ $mode == notarized-apps ]]; then
        verify_stapled_app "$mounted_app"
        installed="$work/install-$arch/$app_name"
        mkdir "$work/install-$arch"
        ditto "$mounted_app" "$installed"
        xattr -w com.apple.quarantine "$quarantine" "$installed"
        verify_stapled_app "$installed"
    fi
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
