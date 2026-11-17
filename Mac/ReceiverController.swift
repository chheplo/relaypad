import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class ReceiverController: ObservableObject {
    let link = MacLink()
    @Published private(set) var accessibilityAllowed = AXIsProcessTrusted()
    @Published private(set) var requestedPermission = false

    private let input = InputInjector()
    private var observers: Set<AnyCancellable> = []

    init() {
        link.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &observers)
        link.onEvent = { [weak self] event in
            guard let self, self.accessibilityAllowed else { return }
            self.input.handle(event)
        }
        link.onDisconnect = { [weak self] in self?.input.releaseAll() }
        link.setCanControl(accessibilityAllowed)
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshPermission() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshPermission() }
            .store(in: &observers)

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .sink { [weak self] _ in self?.stop() }
                .store(in: &observers)
        }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.stop() }
            .store(in: &observers)
    }

    func start() {
        refreshPermission()
        link.start()
    }

    func stop() {
        input.releaseAll()
        link.stop()
    }

    func requestPermission() {
        if requestedPermission {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            requestedPermission = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        refreshPermission()
    }

    private func refreshPermission() {
        let allowed = AXIsProcessTrusted()
        guard allowed != accessibilityAllowed else { return }
        if !allowed { input.releaseAll() }
        accessibilityAllowed = allowed
        link.setCanControl(allowed)
    }
}
