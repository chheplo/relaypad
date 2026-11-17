import SwiftUI
import UIKit

@main
struct RelaypadPhoneApp: App {
    @StateObject private var link: PhoneLink
    @StateObject private var controls: RemoteControls
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let connection = PhoneLink()
        _link = StateObject(wrappedValue: connection)
        _controls = StateObject(wrappedValue: RemoteControls(link: connection))
    }

    var body: some Scene {
        WindowGroup {
            RemoteDeck(link: link, controls: controls)
                .preferredColorScheme(.dark)
                .onAppear { link.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { link.start() }
                    else {
                        controls.reset()
                        if phase == .background { link.stop() }
                    }
                }
                .onChange(of: link.canControl) { _, allowed in
                    if !allowed { controls.reset() }
                }
        }
    }
}

enum DeckColor {
    static let base = Color(red: 0.075, green: 0.080, blue: 0.083)
    static let panel = Color(red: 0.122, green: 0.132, blue: 0.137)
    static let keyTop = Color(red: 0.235, green: 0.247, blue: 0.250)
    static let keyBottom = Color(red: 0.186, green: 0.196, blue: 0.200)
    static let ink = Color(red: 0.94, green: 0.933, blue: 0.90)
    static let muted = Color(red: 0.68, green: 0.69, blue: 0.68)
    static let amber = Color(red: 1.0, green: 0.716, blue: 0.383)
    static let outline = Color.white.opacity(0.115)
}

private struct RelayMark: View {
    var body: some View {
        Canvas { ctx, size in
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
                let box = CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
                ctx.fill(Path(roundedRect: box, cornerRadius: r), with: .color(DeckColor.amber))
            }
            rect(0, 0.12, 0.58, 0.76, 3)
            for i in 0..<3 { rect(0.68, 0.12 + Double(i) * 0.285, 0.32, 0.19, 1.2) }
        }
        .accessibilityHidden(true)
    }
}

private enum DeckSheet: String, Identifiable {
    case connection, settings, keyboard, gestures
    var id: Self { self }
}

private struct RemoteDeck: View {
    @ObservedObject var link: PhoneLink
    @ObservedObject var controls: RemoteControls
    @State private var sheet: DeckSheet?

    private var canSend: Bool { link.isConnected && link.canControl }
    private var connectionTitle: String {
        if link.isConnected { return link.canControl ? (link.connectedName ?? "Connected") : "Enable input" }
        return link.isConnecting ? "Connecting" : "Pair Mac"
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = 12
            let gap: CGFloat = 8
            let availableWidth = geo.size.width - 2 * side - gap
            let keyRailWidth = max(94, availableWidth * 0.2)
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    RelayMark().frame(width: 25, height: 25)
                    Text("Relaypad")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .fixedSize()
                    Spacer(minLength: 0)
                    Group {
                        Button { sheet = canSend ? .keyboard : .connection } label: {
                            Label("Keyboard", systemImage: "keyboard")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Keyboard")
                        Button { sheet = .gestures } label: {
                            Label("Gestures", systemImage: "hand.draw")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Gestures")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DeckColor.muted)
                    .labelStyle(HeaderLabelStyle(iconsOnly: geo.size.width < 600))
                    .fixedSize()
                    Button {
                        sheet = .connection
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(canSend ? Color.mint : DeckColor.amber).frame(width: 7, height: 7)
                            Text(connectionTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 11).frame(height: 34)
                        .background(Capsule().fill(DeckColor.panel))
                        .overlay(Capsule().stroke(DeckColor.outline, lineWidth: 1))
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Connection, " + connectionTitle)
                    Button { sheet = .settings } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings.open")
                }
                HStack(spacing: gap) {
                    trackpad
                        .frame(maxWidth: .infinity)
                    keys
                        .frame(width: keyRailWidth)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(DeckColor.ink)
            .padding(.horizontal, side)
            .padding(.top, 2)
            .padding(.bottom, 3)
        }
        .background(DeckColor.base.ignoresSafeArea())
        .sheet(item: $sheet) { choice in
            Group {
                switch choice {
                case .connection: ConnectionSheet(link: link)
                case .settings: SettingsSheet(controls: controls)
                case .keyboard: KeyboardSheet(link: link)
                case .gestures: GestureSheet()
                }
            }
            .tint(DeckColor.amber)
            .preferredColorScheme(.dark)
        }
        .onChange(of: sheet) { _, next in if next != nil { controls.reset() } }
    }

    private var trackpad: some View {
        ZStack {
            Canvas { ctx, size in
                let dot = Color.white.opacity(0.14)
                let step: CGFloat = 14
                var path = Path()
                for x in stride(from: step / 2, to: size.width, by: step) {
                    for y in stride(from: step / 2, to: size.height, by: step) {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1))
                    }
                }
                ctx.fill(path, with: .color(dot))
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.and.hand.point.up.left")
                    Text("TRACKPAD").tracking(1.4)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeckColor.muted)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(DeckColor.panel.opacity(0.98), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                Spacer()
            }
            PadReticle().frame(width: 38, height: 38)
            TrackSurface(sensitivity: controls.sensitivity, haptics: controls.haptics) { event in
                if canSend { link.send(event) }
                else if case .click = event { sheet = .connection }
            }
            .accessibilityElement()
            .accessibilityLabel("Trackpad")
            .accessibilityIdentifier("trackpad")
            .accessibilityHint("Use the adjustable action to move horizontally, or choose a pointer action.")
            .accessibilityAdjustableAction { direction in
                if canSend { link.send(.move(dx: direction == .increment ? 28 : -28, dy: 0)) }
            }
            .accessibilityAction(named: "Move up") { if canSend { link.send(.move(dx: 0, dy: -28)) } }
            .accessibilityAction(named: "Move down") { if canSend { link.send(.move(dx: 0, dy: 28)) } }
            .accessibilityAction(named: "Click") { click(.left) }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                mouseButton(.left, label: "Left click", leading: true)
                Rectangle().fill(DeckColor.outline).frame(width: 1, height: 18)
                mouseButton(.right, label: "Right click", leading: false)
            }
            .background(DeckColor.keyBottom, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DeckColor.outline).allowsHitTesting(false))
            .padding(7)
        }
        .background(DeckColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(DeckColor.outline).allowsHitTesting(false))
    }

    private func mouseButton(_ button: RemoteButton, label: String, leading: Bool) -> some View {
        Button { click(button) } label: {
            HStack(spacing: 5) {
                MouseMark(left: leading).frame(width: 12, height: 16)
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .foregroundStyle(DeckColor.muted)
    }

    private func click(_ button: RemoteButton) {
        if canSend {
            if controls.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            link.send(.click(button: button, count: 1))
        } else { sheet = .connection }
    }

    private var keys: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    key(row)
                    key(row + 3)
                }
            }
            key(6)
        }
    }

    private func key(_ index: Int) -> some View {
        KeyCap(binding: controls.bindings[index], haptics: controls.haptics) { down in
            if canSend {
                if down { controls.press(index) } else { controls.release(index) }
            } else if !down { sheet = .connection }
        }
        .accessibilityIdentifier("shortcut.\(index)")
    }
}

private struct HeaderLabelStyle: LabelStyle {
    let iconsOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !iconsOnly { configuration.title }
        }
    }
}

private struct KeyCap: View {
    let binding: KeyBinding
    let haptics: Bool
    var change: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        let amber = binding.key == .function && binding.modifiers.isEmpty
        let color = amber ? DeckColor.base : DeckColor.ink
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: amber
                      ? [DeckColor.amber, Color(red: 0.91, green: 0.60, blue: 0.29)]
                      : [DeckColor.keyTop, DeckColor.keyBottom], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(amber ? Color.white.opacity(0.20) : DeckColor.outline)
            VStack(spacing: 2) {
                Text(binding.glyph)
                    .font(.system(size: binding.key == .space || binding.keys.count > 1 ? 22 : 30, weight: .medium, design: .rounded))
                    .minimumScaleFactor(0.46).lineLimit(1)
                if !binding.subtitle.isEmpty {
                    Text(binding.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color.opacity(amber ? 0.78 : 0.72))
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            .padding(.horizontal, 4)
            .foregroundStyle(color)
            PressSurface { down in
                pressed = down
                if down && haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65) }
                change(down)
            }
        }
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
        .scaleEffect(pressed ? 0.96 : 1)
        .brightness(pressed ? -0.05 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(binding.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { change(true); change(false) }
    }
}

private struct PadReticle: View {
    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var line = Path()
            for direction in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)] {
                line.move(to: CGPoint(x: center.x + 6 * direction.x, y: center.y + 6 * direction.y))
                line.addLine(to: CGPoint(x: center.x + 14 * direction.x, y: center.y + 14 * direction.y))
            }
            ctx.stroke(line, with: .color(DeckColor.muted.opacity(0.42)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6)),
                     with: .color(DeckColor.amber.opacity(0.8)))
        }
        .accessibilityHidden(true)
    }
}

private struct MouseMark: View {
    let left: Bool
    var body: some View {
        Canvas { ctx, size in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let outer = Path(roundedRect: box, cornerRadius: 4)
            ctx.stroke(outer, with: .color(DeckColor.muted), lineWidth: 1)
            ctx.clip(to: outer)
            let half = CGRect(x: left ? box.minX : box.midX, y: box.minY, width: box.width / 2, height: box.height * 0.48)
            ctx.fill(Path(half), with: .color(DeckColor.muted))
        }
        .accessibilityHidden(true)
    }
}
