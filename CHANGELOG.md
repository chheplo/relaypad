# Changelog

## 1.0.0

Relaypad’s first iPhone and Mac release line uses local protocol v1. The two apps can update independently while they support this protocol. [Downloads and availability](https://chheplo.github.io/relaypad/#downloads) · [Protocol v1](docs/protocol-v1.md)

- Turn an iPhone running iOS 17 or later into a landscape trackpad for macOS 14 or later. Move, click, double-click, scroll with two fingers and hold to drag.
- Use seven remappable keys, including a full-width Space bar. Hold modifiers across touches, send Fn twice, or select a preset for Codex, Claude Code or Wispr Flow. Earlier six-key preferences retain their mappings when the app adds Space.
- Send a longer passage through the iPhone keyboard to the focused Mac app. Adjust pointer sensitivity and haptics on the phone.
- Discover a Mac with Bonjour and pair over authenticated TLS using its 12-character code. The iPhone groups the code with automatic hyphens as you type or paste. Saved phones reconnect automatically. The receiver releases held inputs on disconnect and lets you revoke saved pairings by rotating the code.
- Build the native apps from the Xcode project. The Mac packaging script produces distinct Apple silicon and Intel images and verifies Developer ID signing, notarization, stapling and checksums in release mode.
- iPhone build 5 keeps the insertion point after newly formatted text when pasting over a selection in the pairing code. Backspace removes the preceding symbol at a group separator. It pairs with Mac build 4 using protocol v1.
