# Changelog

## 1.0.5 for iPhone

- On first launch, Relaypad for iPhone explains how to install the Mac receiver and lets you send the download link to your Mac. The link is also available in Connection and Settings. [Setup screen](release-assets/web/iphone-mac-setup.webp)

## 1.0.4

Relaypad’s first iPhone and Mac release line uses local protocol v1. The two apps can update independently while they support this protocol. [Downloads and availability](https://chheplo.github.io/relaypad/#downloads) · [Protocol v1](docs/protocol-v1.md)

- On iPhone, open **Settings → About Relaypad → Privacy policy** to read how pairing and input data are handled.
- Turn an iPhone running iOS 17 or later into a landscape trackpad for macOS 14 or later. Move, click, double-click, scroll with two fingers and hold to drag.
- Use seven remappable keys, including a full-width Space bar. Hold modifiers across touches, send Fn twice, or select a preset for Codex, Claude Code or Wispr Flow. Earlier six-key preferences retain their mappings when the app adds Space.
- Send a longer passage through the iPhone keyboard to the focused Mac app. Adjust pointer sensitivity and haptics on the phone.
- Discover a Mac with Bonjour and pair over authenticated TLS using its 12-character code. The iPhone groups the code with automatic hyphens as you type or paste. Saved phones reconnect automatically. The receiver releases held inputs on disconnect and lets you revoke saved pairings by rotating the code.
- Build the native apps from the Xcode project. The Mac packaging script produces distinct Apple silicon and Intel images and verifies Developer ID signing, notarization, stapling and checksums in release mode.
- Pasting over a selected part of the pairing code keeps the insertion point after the replacement, including automatic hyphens. Backspace at a separator removes the preceding symbol.
- Both apps show the public version 1.0.4 in About. Internal build numbers remain available in bundle metadata for distribution.
