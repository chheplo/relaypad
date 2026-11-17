import AppKit
import SwiftUI

@main
struct RelaypadMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var receiver = ReceiverController()

    var body: some Scene {
        Window("Relaypad for Mac", id: "receiver") {
            ReceiverWindow(receiver: receiver)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Relaypad") { openWindow(id: "about") }
            }
            CommandMenu("Receiver") {
                Button(receiver.link.isRunning ? "Stop Receiver" : "Start Receiver") {
                    if receiver.link.isRunning { receiver.stop() } else { receiver.start() }
                }
            }
        }
        Window("About Relaypad", id: "about") {
            VStack(alignment: .leading, spacing: 15) {
                Text("Relaypad for Mac").font(.title2.bold())
                Divider()
                AboutRows()
            }
            .padding(24)
            .frame(width: 356)
            .fixedSize(horizontal: false, vertical: true)
        }
        .windowResizability(.contentSize)
        MenuBarExtra {
            ReceiverMenu(receiver: receiver)
        } label: {
            Label("Relaypad", systemImage: receiver.link.clientName == nil ? "magicmouse" : "magicmouse.fill")
        }
    }
}

private struct ReceiverMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var receiver: ReceiverController

    var body: some View {
        if let phone = receiver.link.clientName {
            Text("Connected to \(phone)")
        } else {
            Text(receiver.link.isRunning ? receiver.link.statusMessage : "Receiver off")
        }
        Button("Open Relaypad") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "receiver")
        }
        Button(receiver.link.isRunning ? "Stop Receiver" : "Start Receiver") {
            if receiver.link.isRunning { receiver.stop() } else { receiver.start() }
        }
        Divider()
        Button("Quit Relaypad") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
