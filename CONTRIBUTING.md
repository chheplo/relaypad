# Contributing to Relaypad

Relaypad has two native Swift targets in one Xcode project. `Phone/` contains the iPhone controls and connection browser, `Mac/` contains the receiver and input driver, and `Shared/` defines the local wire protocol and pairing storage.

## Build from source

Use Xcode 26.2 or a compatible newer Xcode. There are no external Swift packages to install.

```sh
git clone https://github.com/chheplo/relaypad.git
cd relaypad
open Relaypad.xcodeproj
```

- **Mac receiver** — Choose the **Relaypad for Mac** scheme, select **My Mac** and press **Run**. To build locally from Terminal, run `xcodebuild -project Relaypad.xcodeproj -scheme 'Relaypad for Mac' -configuration Release -derivedDataPath build/local CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build`. The app is at `build/local/Build/Products/Release/Relaypad for Mac.app`.
- **iPhone app** — Connect your unlocked iPhone to the Mac, trust the computer if prompted, and enable Developer Mode if Xcode requests it. Choose the **Relaypad** scheme and the iPhone as the destination. Under **Signing & Capabilities**, select your development team and choose a unique bundle identifier if your team needs one. Press **Run**. For UI work, an iPhone simulator also runs the app. [Run an app on a device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) · [Enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

## Checks

Run the protocol and Mac input checks from the repository root on a Mac with Xcode selected.

```sh
checks/protocol-v1.sh
xcrun swiftc Shared/RemoteProtocol.swift Mac/InputInjector.swift checks/MacInputTests.swift -o /tmp/relaypad-input-tests
/tmp/relaypad-input-tests
xcrun swiftc Shared/RemoteProtocol.swift Phone/PairingCodeEdit.swift checks/PairingCodeEditingTests.swift -o /tmp/relaypad-code-tests
/tmp/relaypad-code-tests
```

The protocol check exercises the v1 payloads, length prefixes and TLS handshake on loopback. The Mac input check uses an in-memory event collector. In Xcode, select an iPhone simulator, choose the **Relaypad** scheme with the Debug configuration, and use **Product → Test** for the layout and remapping tests. Running the UI tests in Debug gives their remapping test a separate preferences suite.

For changes to pairing or event delivery, also exercise a real pair. Connect, click in an empty editor, type `123` and a space, double-tap Fn, disconnect while holding a modifier, then reconnect. Use a previously released v1 counterpart when checking a change to just one app. Keep fixed v1 samples in the compatibility test even when a new app layout ships. [Protocol and compatibility policy](docs/protocol-v1.md)

## Mac release disk images

Run `scripts/package-macos.sh preview` for ad-hoc development images. The `release` mode uses a Developer ID Application certificate and a notarytool Keychain profile to sign and submit the DMGs. Run `scripts/package-macos.sh --help` for its environment settings.

When Xcode has already submitted the Apple silicon and Intel app archives for notarization, retrieve those submissions and package the results with the following command. Use the original submitted archives, in architecture order.

```sh
scripts/package-macos.sh notarized-apps /path/to/arm64.xcarchive /path/to/x86_64.xcarchive
```

This mode calls `xcodebuild -exportNotarizedApp` to retrieve the existing results. If Apple is still processing them, rerun the same command after tickets become available. It also accepts paths to two already-exported, stapled app bundles. This route produces unsigned, read-only DMG containers holding the Developer ID–signed and notarized apps. The script checks the app tickets, both architectures, the matching release identities, and Gatekeeper assessment of the mounted and installed copies. It writes both verified images and `SHA256SUMS` together. In the output directory, run `shasum -a 256 -c SHA256SUMS` before publishing the release assets.

## App versions

Set the public release number in `MARKETING_VERSION` in `Config/Base.xcconfig`. Both About views display that value. Increment `CURRENT_PROJECT_VERSION` for a new distribution build. Keep the wire protocol version independent of either number and record user-visible changes in the changelog.

## Publishing download links

The website reads `docs/site-release.json`. Each of the three channels has a `version` and a `url`. Leave them null until the corresponding download has been publicly verified. Use the production App Store listing for iPhone and architecture-specific GitHub Releases DMG URLs for macOS. A source-build link remains available for any channel without a verified download. Update the iPhone, Apple silicon and Intel entries independently when their releases go live.

## Branches and pull requests

Start a short-lived `feature/<name>` or `fix/<name>` branch from the latest `main`. Open a pull request back to `main`. Maintainers use `release/v<version>` to prepare release notes, packaging and compatibility checks for a version. The required `build` check must pass before merging a pull request. Keep the branch up to date with `main` when GitHub asks. Merged topic branches are deleted automatically.

Tag the tested release commit as `v<version>` when distributing its official artifacts. The download manifest tracks the publication of each platform separately.

Describe the user-visible change and the checks you ran. Include the affected platform and a screenshot for UI changes. Use sample device names and closed test sessions for screenshots showing pairing. Keep changes to the seven-key preferences compatible with existing users' saved mappings.

## Security reports

Keep live pairing codes and sensitive findings private. If the repository’s **Security** tab offers **Report a vulnerability**, send the affected versions, impact and a minimal description there. Otherwise, open an issue asking the maintainer for a private contact and share the details through that channel. If a pairing code has leaked, choose **New code** on the Mac. [Repository security](https://github.com/chheplo/relaypad/security)
