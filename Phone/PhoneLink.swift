import Combine
import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

struct RemoteHost: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
}

final class PhoneLink: ObservableObject {
    @Published private(set) var hosts = [RemoteHost]()
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var statusMessage = "Searching for Macs…"
    @Published private(set) var connectedName: String?
    @Published private(set) var canControl = false

    private static let lastIDKey = "Relaypad.LastReceiver"
    private var desiredID = UserDefaults.standard.string(forKey: lastIDKey)
    private var autoPairingBlocked = false
    private var attemptedID: String?
    private var browser: NWBrowser?
    private var channel: SecureChannel?
    private var retry: DispatchWorkItem?
    private var retryDelay: Double = 1
    private var isActive = false

    func start() {
        guard browser == nil else { return }
        isActive = true
        autoPairingBlocked = false
        statusMessage = "Searching for Macs…"
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let discovery = NWBrowser(for: .bonjourWithTXTRecord(type: LocalService.type, domain: "local."),
                                  using: parameters)
        browser = discovery
        discovery.stateUpdateHandler = { [weak self, weak discovery] state in
            guard let self, let discovery, self.browser === discovery else { return }
            switch state {
            case .waiting:
                if self.channel == nil {
                    self.statusMessage = "Allow Local Network access in Settings and join your Mac’s Wi-Fi."
                }
            case .failed(let error):
                self.browser = nil
                discovery.cancel()
                self.hosts = []
                self.statusMessage = "Couldn’t search the local network. " + error.localizedDescription
                self.scheduleRetry()
            default:
                break
            }
        }
        discovery.browseResultsChangedHandler = { [weak self, weak discovery] results, _ in
            guard let self, let discovery, self.browser === discovery else { return }
            var unique = [String: RemoteHost]()
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint,
                      case let .bonjour(txt) = result.metadata,
                      let id = txt["id"], UUID(uuidString: id) != nil else { continue }
                unique[id] = RemoteHost(id: id, name: name, endpoint: result.endpoint)
            }
            self.hosts = unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if self.channel == nil && self.retry == nil && !self.autoPairingBlocked {
                self.statusMessage = self.hosts.isEmpty ? "Searching for Macs…" : "Choose a Mac to connect."
            }
            self.autoConnectIfAvailable()
        }
        discovery.start(queue: .main)
    }

    func stop() {
        isActive = false
        cancelRetry()
        let discovery = browser
        browser = nil
        discovery?.cancel()
        hosts = []
        closeCurrent()
        statusMessage = "Disconnected."
    }

    func hasSavedCode(for host: RemoteHost) -> Bool {
        PairingStore.read(host.id).flatMap(PairingCode.normalized) != nil
    }

    func connect(to host: RemoteHost, code: String) {
        let input = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = PairingStore.read(host.id).flatMap(PairingCode.normalized)
        guard let secret = input.isEmpty ? saved : PairingCode.normalized(input) else {
            statusMessage = "Enter the 12-character code shown on your Mac."
            return
        }
        cancelRetry()
        autoPairingBlocked = false
        remember(secret == saved ? host.id : nil)
        open(host, secret: secret)
    }

    func disconnect() {
        remember(nil)
        cancelRetry()
        closeCurrent()
        statusMessage = "Disconnected."
    }

    func forget(_ host: RemoteHost) {
        if host.id == desiredID || host.id == attemptedID { disconnect() }
        PairingStore.remove(host.id)
        objectWillChange.send()
    }

    func send(_ event: RemoteEvent) {
        guard isConnected, canControl, event.isValid else { return }
        channel?.send(.input(event))
    }

    private func open(_ host: RemoteHost, secret: String) {
        closeCurrent()
        attemptedID = host.id
        isConnecting = true
        statusMessage = "Connecting to " + host.name + "…"
        let peer = SecureChannel(NWConnection(to: host.endpoint, using: LocalService.parameters(code: secret)))
        channel = peer
        peer.onReady = { [weak peer] in
            #if canImport(UIKit)
            let name = UIDevice.current.name
            #else
            let name = "iPhone"
            #endif
            peer?.send(.hello(version: LocalService.version, name: name))
        }
        peer.onMessage = { [weak self, weak peer] message in
            guard let self, let peer, self.channel === peer else { return }
            switch message {
            case .ready(let allowed):
                if !self.isConnected {
                    let saved = PairingStore.read(host.id) == secret || PairingStore.save(secret, for: host.id)
                    self.remember(saved ? host.id : nil)
                    self.retryDelay = 1
                    self.isConnected = true
                    self.isConnecting = false
                    self.connectedName = host.name
                }
                self.canControl = allowed
                self.statusMessage = allowed ? "Connected to " + host.name + "." : "Enable Accessibility for Relaypad on your Mac."
            case .busy:
                self.closeCurrent()
                if self.desiredID == host.id {
                    // The previous foreground session may still be timing out on the receiver.
                    self.statusMessage = "This Mac is connected to another phone. Retrying your saved connection…"
                    self.scheduleRetry()
                } else {
                    self.autoPairingBlocked = true
                    self.statusMessage = "This Mac is connected to another phone."
                }
            case .heartbeat:
                if !self.isConnected { peer.close(.invalidMessage) }
            default:
                peer.close(.invalidMessage)
            }
        }
        peer.onClose = { [weak self, weak peer] reason in
            guard let self, let peer, self.channel === peer else { return }
            let wasConnected = self.isConnected
            self.closeCurrent()
            if wasConnected {
                self.statusMessage = "Connection lost. Looking for your Mac…"
                self.scheduleRetry()
            } else if reason == .authentication || self.desiredID == nil {
                self.autoPairingBlocked = true
                self.statusMessage = "Couldn’t pair. Check the code on your Mac and try again."
            } else {
                self.statusMessage = "Couldn’t reconnect. Check the receiver and its pairing code."
                self.scheduleRetry()
            }
        }
        peer.start()
    }

    private func closeCurrent() {
        let old = channel
        channel = nil
        old?.close()
        isConnected = false
        isConnecting = false
        canControl = false
        connectedName = nil
        attemptedID = nil
    }

    private func remember(_ id: String?) {
        desiredID = id
        UserDefaults.standard.set(id, forKey: Self.lastIDKey)
    }

    private func autoConnectIfAvailable() {
        guard isActive, channel == nil, retry == nil, !autoPairingBlocked,
              let id = desiredID, let host = hosts.first(where: { $0.id == id }),
              let code = PairingStore.read(id).flatMap(PairingCode.normalized) else { return }
        open(host, secret: code)
    }

    private func scheduleRetry() {
        guard isActive, retry == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.retry = nil
            if self.browser == nil { self.start() }
            self.autoConnectIfAvailable()
        }
        retry = task
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: task)
        retryDelay = min(15, retryDelay * 2)
    }

    private func cancelRetry() {
        retry?.cancel()
        retry = nil
        retryDelay = 1
    }
}
