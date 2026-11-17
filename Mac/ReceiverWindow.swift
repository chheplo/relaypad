import AppKit
import SwiftUI

private enum Ink {
    static let page = Color(red: 0.102, green: 0.106, blue: 0.105)
    static let panel = Color(red: 0.139, green: 0.143, blue: 0.139)
    static let line = Color.white.opacity(0.13)
    static let paper = Color(red: 0.965, green: 0.946, blue: 0.892)
    static let secondary = Color(red: 0.726, green: 0.734, blue: 0.711)
    static let amber = Color(red: 1.0, green: 0.737, blue: 0.420)
    static let green = Color(red: 0.624, green: 0.831, blue: 0.658)
}

struct ReceiverWindow: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var receiver: ReceiverController
    @State private var copied = false
    @State private var confirmingRotation = false
    private var link: MacLink { receiver.link }

    // Give longer network and Keychain messages the full width of the card.
    private var needsStatusDetail: Bool { link.statusMessage.count > 40 }

    private var compactStatus: String {
        if !needsStatusDetail && !link.statusMessage.isEmpty {
            return link.statusMessage.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return link.isRunning ? "Receiver on" : "Receiver off"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 11) {
                PadMark().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Relaypad").font(.system(size: 22, weight: .semibold)).tracking(-0.8)
                    Text("Mac receiver").font(.system(size: 12)).foregroundStyle(Ink.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(link.clientName != nil ? Ink.green : (link.isRunning ? Ink.amber : Ink.secondary))
                        .frame(width: 7, height: 7)
                    Text(compactStatus)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(Ink.panel))
                .overlay(Capsule().strokeBorder(Ink.line))
                Button { openWindow(id: "about") } label: {
                    Image(systemName: "info.circle").font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.secondary)
                .accessibilityLabel("About Relaypad")
                .help("About Relaypad")
            }

            VStack(alignment: .leading, spacing: 17) {
                Image(systemName: link.clientName == nil ? "iphone.and.arrow.forward" : "iphone.radiowaves.left.and.right")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(Ink.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(heroTitle)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(heroDescription)
                        .foregroundStyle(Ink.secondary)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if link.isRunning && link.clientName == nil && !link.pairingCode.isEmpty {
                    pairingField
                }
                HStack(spacing: 16) {
                    if link.isRunning {
                        Button("Stop receiver", action: receiver.stop)
                            .buttonStyle(ConsoleButton())
                        Button("New code…") { confirmingRotation = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(Ink.secondary)
                            .help("Replace the saved pairing code")
                    } else {
                        Button("Start receiver", action: receiver.start)
                            .buttonStyle(ConsoleButton(primary: true))
                    }
                }
                if needsStatusDetail {
                    Text(link.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 18).fill(Ink.panel))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ink.line))

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: receiver.accessibilityAllowed ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 20))
                    .frame(width: 30)
                    .foregroundStyle(receiver.accessibilityAllowed ? Ink.green : Ink.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility access").font(.headline)
                    Text(receiver.accessibilityAllowed
                         ? "Allowed for pointer and keyboard input."
                         : "Allow Relaypad to control the pointer and keyboard.")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !receiver.accessibilityAllowed {
                    Button(receiver.requestedPermission ? "Open Settings" : "Allow access",
                           action: receiver.requestPermission)
                        .buttonStyle(ConsoleButton())
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 36)
        .padding(.bottom, 26)
        .frame(width: 496)
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.page)
        .foregroundStyle(Ink.paper)
        .preferredColorScheme(.dark)
        .tint(Ink.amber)
        .onChange(of: link.pairingCode) { _, _ in copied = false }
        .confirmationDialog("Replace the pairing code?", isPresented: $confirmingRotation) {
            Button("Replace code", role: .destructive) { link.rotateCode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any connected phone will disconnect. Enter the new code on each phone you want to use.")
        }
    }

    private var heroTitle: String {
        if let client = link.clientName { return client }
        return link.isRunning ? "Pair your iPhone" : "Connect your iPhone"
    }

    private var heroDescription: String {
        if link.clientName != nil {
            return receiver.accessibilityAllowed
                ? "Connected. Use the trackpad and keys on your iPhone to control this Mac."
                : "Connected. Allow Accessibility access below to enable the trackpad and keys."
        }
        if link.isRunning {
            let destination = link.advertisedName.map { "“\($0)”" } ?? "this Mac"
            return "Open Relaypad on your iPhone, choose \(destination), and enter the pairing code."
        }
        return "Join the same Wi-Fi network on both devices, then start the receiver to pair."
    }

    private var pairingField: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pairing code").font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.secondary)
                Text(link.pairingCode)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundStyle(Ink.paper)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code")
                    .accessibilityValue(link.pairingCode.map(String.init).joined(separator: " "))
            }
            Spacer(minLength: 4)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                copied = pasteboard.setString(link.pairingCode, forType: .string)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(ConsoleButton())
            .accessibilityLabel(copied ? "Code copied" : "Copy pairing code")
            .help(copied ? "Code copied" : "Copy pairing code")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.page))
    }
}

private struct ConsoleButton: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? Ink.page : Ink.paper)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? Ink.amber : Color.white.opacity(0.07))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : Ink.line))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct PadMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(Ink.amber)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(Ink.page).frame(width: 13, height: 20)
                VStack(spacing: 1.5) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 1.5) {
                            ForEach(0..<2) { _ in
                                RoundedRectangle(cornerRadius: 1).fill(Ink.page).frame(width: 4, height: 5.7)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
