import Combine
import Foundation
import Network

final class MacLink: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var clientName: String?
    @Published private(set) var advertisedName: String?
    @Published private(set) var statusMessage = "Receiver is off."
    @Published private(set) var pairingCode: String

    var onEvent: ((RemoteEvent) -> Void)?
    var onDisconnect: (() -> Void)?

    private static let credential = "mac-receiver"
    private let receiverID: String
    private var code: String
    private var codeIsSaved: Bool
    private var canControl = false
    private var listener: NWListener?
    private var channels = [UUID: SecureChannel]()
    private var activeID: UUID?

    init() {
        let stored = PairingStore.read(Self.credential).flatMap(PairingCode.normalized)
        let secret = stored ?? PairingCode.generate()
        code = secret
        pairingCode = PairingCode.display(secret)
        codeIsSaved = stored != nil || PairingStore.save(secret, for: Self.credential)

        let defaults = UserDefaults.standard
        let idKey = "Relaypad.ReceiverID"
        let id = defaults.string(forKey: idKey) ?? UUID().uuidString
        defaults.set(id, forKey: idKey)
        receiverID = id
    }

    private var waitingMessage: String {
        codeIsSaved ? "Waiting for your iPhone." : "Waiting for your iPhone. This code is valid for this launch."
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = LocalService.parameters(code: code)
            parameters.acceptLocalOnly = true
            let service = try NWListener(using: parameters)
            listener = service
            isRunning = true
            statusMessage = "Starting receiver…"
            service.service = NWListener.Service(type: LocalService.type, domain: "local.",
                                                 txtRecord: NWTXTRecord(["id": receiverID]))
            service.serviceRegistrationUpdateHandler = { [weak self, weak service] change in
                guard let self, let service, self.listener === service else { return }
                switch change {
                case .add(.service(let name, _, _, _)):
                    self.advertisedName = name
                case .remove(.service(let name, _, _, _)) where self.advertisedName == name:
                    self.advertisedName = nil
                default:
                    break
                }
            }
            service.newConnectionHandler = { [weak self, weak service] incoming in
                guard let self, let service, self.listener === service else { incoming.cancel(); return }
                self.accept(incoming)
            }
            service.stateUpdateHandler = { [weak self, weak service] state in
                guard let self, let service, self.listener === service else { return }
                switch state {
                case .ready:
                    if self.activeID == nil { self.statusMessage = self.waitingMessage }
                case .waiting:
                    self.statusMessage = "Waiting for the local network. Check Local Network access in System Settings."
                case .failed(let error):
                    self.stop()
                    self.statusMessage = "Couldn’t start the receiver. " + error.localizedDescription
                default:
                    break
                }
            }
            service.start(queue: .main)
        } catch {
            isRunning = false
            statusMessage = "Couldn’t start the receiver. " + error.localizedDescription
        }
    }

    func stop() {
        let service = listener
        listener = nil
        service?.cancel()
        advertisedName = nil
        for channel in Array(channels.values) { channel.close() }
        isRunning = false
        statusMessage = "Receiver is off."
    }

    func rotateCode() {
        let replacement = PairingCode.generate()
        let saved = PairingStore.save(replacement, for: Self.credential)
        guard saved else {
            statusMessage = "Unlock the Mac keychain to change the pairing code."
            return
        }
        let resume = isRunning
        stop()
        code = replacement
        codeIsSaved = saved
        pairingCode = PairingCode.display(replacement)
        if resume { start() }
    }

    func setCanControl(_ allowed: Bool) {
        guard canControl != allowed else { return }
        canControl = allowed
        if let id = activeID {
            if !allowed { onDisconnect?() }
            channels[id]?.send(.ready(canControl: allowed))
        }
    }

    private func accept(_ incoming: NWConnection) {
        guard channels.count < 5 else { incoming.cancel(); return }
        let id = UUID()
        let channel = SecureChannel(incoming)
        channels[id] = channel
        channel.onMessage = { [weak self, weak channel] message in
            guard let self, let channel else { return }
            switch message {
            case let .hello(version, name):
                guard version == LocalService.version else { channel.close(.invalidMessage); return }
                if self.activeID != nil {
                    channel.send(.busy) { [weak channel] in channel?.close() }
                    return
                }
                let printable = name.components(separatedBy: .controlCharacters).joined().prefix(64)
                let label = printable.isEmpty ? "iPhone" : String(printable)
                self.activeID = id
                self.clientName = label
                self.statusMessage = "Connected to " + label + "."
                channel.send(.ready(canControl: self.canControl))
            case let .input(event):
                guard self.activeID == id, event.isValid else { channel.close(.invalidMessage); return }
                if self.canControl { self.onEvent?(event) }
            case .heartbeat:
                guard self.activeID == id else { channel.close(.invalidMessage); return }
            default:
                channel.close(.invalidMessage)
            }
        }
        channel.onClose = { [weak self] _ in
            guard let self else { return }
            self.channels.removeValue(forKey: id)
            guard self.activeID == id else { return }
            self.activeID = nil
            self.clientName = nil
            self.onDisconnect?()
            self.statusMessage = self.waitingMessage
        }
        channel.start()
    }
}
