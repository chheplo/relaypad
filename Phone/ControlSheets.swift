import SwiftUI

private struct CloseSheetItem: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
    }
}

struct ConnectionSheet: View {
    @ObservedObject var link: PhoneLink
    @State private var selected: RemoteHost?
    @State private var code = ""
    @State private var focusCode = false

    var body: some View {
        NavigationStack {
            List {
                if link.isConnected {
                    Section {
                        Label(link.connectedName ?? "Mac", systemImage: "desktopcomputer")
                            .font(.headline)
                        Label(link.canControl ? "Ready for input" : "Input permission needed",
                              systemImage: link.canControl ? "checkmark.circle" : "lock")
                            .foregroundStyle(link.canControl ? Color.mint : DeckColor.amber)
                    } footer: {
                        if !link.canControl {
                            Text("On your Mac, open Relaypad and grant Accessibility access in System Settings.")
                        }
                    }
                    Section { Button("Disconnect", role: .destructive) { link.disconnect(); selected = nil; code = "" } }
                } else {
                    Section {
                        if link.hosts.isEmpty {
                            HStack { ProgressView(); Text("Looking for Macs…").padding(.leading, 6) }
                        }
                        ForEach(link.hosts) { host in
                            Button {
                                selected = host
                                code = ""
                                if link.hasSavedCode(for: host) { link.connect(to: host, code: "") }
                                else { focusCode = true }
                            } label: {
                                HStack {
                                    Label(host.name, systemImage: "desktopcomputer")
                                    Spacer()
                                    Image(systemName: selected?.id == host.id ? "checkmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(selected?.id == host.id ? DeckColor.amber : DeckColor.muted)
                                }
                            }
                            .foregroundStyle(DeckColor.ink)
                            .disabled(link.isConnecting)
                        }
                    } header: {
                        Text("Nearby Macs")
                    } footer: {
                        Text("Open Relaypad for Mac. Connect both devices to the same local network and allow Local Network access.")
                    }

                    if let host = selected {
                        Section {
                            PairingCodeField(text: $code, focused: $focusCode) {
                                if validCode && !link.isConnecting { connect(host) }
                            }
                            .frame(minHeight: 34)
                            Button {
                                connect(host)
                            } label: {
                                HStack {
                                    Text(link.isConnecting ? "Connecting…" : "Connect")
                                    if link.isConnecting { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(!validCode || link.isConnecting)
                            if link.hasSavedCode(for: host) {
                                Button("Forget saved code", role: .destructive) {
                                    link.forget(host)
                                    code = ""
                                    focusCode = true
                                }
                                .disabled(link.isConnecting)
                            }
                        } header: {
                            Text("Pair with " + host.name)
                        } footer: {
                            Text("Enter the pairing code shown in the Mac app.")
                        }
                    }
                    if !link.statusMessage.isEmpty {
                        Section { Text(link.statusMessage).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheetItem() }
            .onChange(of: link.isConnected) { _, connected in if connected { focusCode = false; code = "" } }
        }
    }

    private var validCode: Bool { PairingCode.normalized(code) != nil }
    private func connect(_ host: RemoteHost) {
        focusCode = false
        link.connect(to: host, code: code)
    }
}

struct SettingsSheet: View {
    @ObservedObject var controls: RemoteControls
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(controls.bindings.indices, id: \.self) { index in
                        NavigationLink {
                            BindingEditor(controls: controls, index: index)
                        } label: {
                            HStack {
                                Text("Key \(index + 1)")
                                Spacer()
                                Text(controls.bindings[index].name).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("binding.\(index)")
                    }
                } header: {
                    Text("Shortcut keys")
                } footer: {
                    Text("Hold a modifier while tapping another key. Tap fn twice for apps configured to use a double tap.")
                }
                Section("Trackpad") {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Pointer speed")
                            Spacer()
                            Text(controls.sensitivity, format: .number.precision(.fractionLength(1))).monospacedDigit()
                            Text("×").foregroundStyle(.secondary)
                        }
                        Slider(value: $controls.sensitivity, in: 0.5...3, step: 0.1)
                            .accessibilityLabel("Pointer speed")
                    }
                    .padding(.vertical, 4)
                    Toggle("Touch feedback", isOn: $controls.haptics)
                }
                Section {
                    Button("Restore default keys") { confirmRestore = true }
                        .confirmationDialog("Restore all seven default keys?", isPresented: $confirmRestore, titleVisibility: .visible) {
                            Button("Restore keys", role: .destructive) { controls.restoreKeys() }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                Section("About Relaypad") {
                    AboutRows()
                    Link(destination: URL(string: "https://chheplo.github.io/relaypad/privacy.html")!) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("about.privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheetItem() }
        }
    }
}

private struct BindingEditor: View {
    @ObservedObject var controls: RemoteControls
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: KeyBinding

    init(controls: RemoteControls, index: Int) {
        self.controls = controls
        self.index = index
        _draft = State(initialValue: controls.bindings[index])
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Key", selection: Binding(get: { draft.key }, set: {
                    draft.key = $0
                    draft.modifiers.removeAll { $0 == draft.key }
                    draft.title = ""
                })) {
                    ForEach(PadKey.allCases) { key in Text(key.name).tag(key) }
                }
                .pickerStyle(.navigationLink)
                HStack {
                    Text("Modifiers")
                    Spacer()
                    ForEach(PadKey.modifiers) { key in
                        Button {
                            if draft.modifiers.contains(key) { draft.modifiers.removeAll { $0 == key } }
                            else { draft.modifiers.append(key) }
                            draft.title = ""
                        } label: {
                            Text(key.glyph)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(minWidth: 26, minHeight: 40)
                                .foregroundStyle(draft.modifiers.contains(key) ? DeckColor.amber : DeckColor.muted)
                                .background(draft.modifiers.contains(key) ? DeckColor.amber.opacity(0.1) : .clear, in: Capsule())
                        }
                        .buttonStyle(.borderless).disabled(key == draft.key)
                        .accessibilityLabel(key.name)
                        .accessibilityValue(draft.modifiers.contains(key) ? "Selected" : "Off")
                    }
                }
                TextField("Optional key label", text: $draft.title).submitLabel(.done)
                    .accessibilityLabel("Key label")
            }
            ForEach(KeyBinding.presets, id: \.0) { group, bindings in
                Section {
                    ForEach(bindings, id: \.title) { binding in
                        Button {
                            draft = binding
                        } label: {
                            HStack {
                                Text(binding.title).foregroundStyle(DeckColor.ink)
                                Spacer()
                                Text(binding.glyph).foregroundStyle(.secondary)
                                if draft == binding { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text(group)
                } footer: {
                    if group == "Wispr Flow" { Text("Choose the shortcut configured in Wispr Flow on your Mac.") }
                }
            }
        }
        .navigationTitle("Key \(index + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { controls.save(draft, at: index); dismiss() }
            }
        }
    }
}

struct KeyboardSheet: View {
    @ObservedObject var link: PhoneLink
    @State private var text = ""
    @FocusState private var editing: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text to send", text: $text, axis: .vertical)
                        .lineLimit(2...8).focused($editing)
                        .accessibilityLabel("Text to send")
                } footer: {
                    if !RemoteEvent.text(text).isValid {
                        Text("This message is too long. Send it in smaller pieces.")
                            .foregroundStyle(DeckColor.amber)
                    } else {
                        Text("Text goes to the active field on your Mac. You can also use dictation on your iPhone keyboard.")
                    }
                }
            }
            .navigationTitle("Type on Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        link.send(.text(text))
                        dismiss()
                    }
                    .disabled(text.isEmpty || !RemoteEvent.text(text).isValid || !link.isConnected || !link.canControl)
                }
            }
            .onAppear { editing = true }
        }
    }
}

struct GestureSheet: View {
    private let gestures = [
        ("Move pointer", "Slide one finger", "hand.draw"),
        ("Click", "Tap the pad once with one finger", "hand.tap"),
        ("Double-click", "Tap twice quickly", "hand.tap.fill"),
        ("Right-click", "Tap the Right click button in the corner of the pad", "hand.point.up.left"),
        ("Scroll", "Slide two fingers", "arrow.up.and.down"),
        ("Drag", "Hold briefly, then slide one finger", "hand.point.up.left.fill"),
        ("Combine keys", "Hold a modifier and tap a second key", "command")
    ]
    var body: some View {
        NavigationStack {
            List(gestures, id: \.0) { title, detail, symbol in
                HStack(spacing: 14) {
                    Image(systemName: symbol).foregroundStyle(DeckColor.amber).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            .navigationTitle("Gestures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseSheetItem() }
        }
    }
}
