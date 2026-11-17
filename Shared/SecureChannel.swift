import CryptoKit
import Foundation
import Network
import Security

enum LocalService {
    static let type = "_relaypad._tcp"
    static let version = 1
    static let cipher = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!

    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        // Network.framework authenticates both peers using a pre-shared key with TLS 1.2.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, cipher)
        let identity = Data("Relaypad-1".utf8)
        let secret = HMAC<SHA256>.authenticationCode(for: identity, using: SymmetricKey(data: Data(code.utf8)))
        let keyData = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, keyData as __DispatchData, identityData as __DispatchData)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

enum LinkFailure {
    case authentication, transport, timeout, invalidMessage
}

/// A length-prefixed, authenticated stream. Handlers and all channel operations run on the main queue.
final class SecureChannel {
    private static let maxFrame = 100_000
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((LinkMessage) -> Void)?
    var onClose: ((LinkFailure) -> Void)?

    private var inbox = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var ready = false
    private var closed = false
    private var outstandingSends = 0
    private var lastReceived = ProcessInfo.processInfo.systemUptime
    private var timer: DispatchSourceTimer?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                guard let meta = self.connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
                      sec_protocol_metadata_get_negotiated_tls_ciphersuite(meta.securityProtocolMetadata) == LocalService.cipher
                else { self.close(.authentication); return }
                self.ready = true
                self.lastReceived = ProcessInfo.processInfo.systemUptime
                self.receive()
                self.onReady?()
            case .failed(let error):
                if case .tls = error { self.close(.authentication) } else { self.close(.transport) }
            case .cancelled:
                self.close(.transport)
            default:
                break
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer = timer
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastReceived > 10 {
                self.close(.timeout)
            } else if self.ready {
                self.send(.heartbeat)
            }
        }
        timer.resume()
        connection.start(queue: .main)
    }

    func send(_ message: LinkMessage, completion: (() -> Void)? = nil) {
        guard ready, !closed else { return }
        guard outstandingSends < 256, let payload = try? encoder.encode(message),
              payload.count <= Self.maxFrame else { close(.transport); return }
        var size = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        outstandingSends += 1
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.outstandingSends -= 1
            if error != nil { self.close(.transport) } else { completion?() }
        })
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, eof, error in
            guard let self, !self.closed else { return }
            if let data {
                self.inbox.append(data)
                while self.inbox.count >= 4 {
                    let size = self.inbox.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                    guard (1...Self.maxFrame).contains(size) else { self.close(.invalidMessage); return }
                    guard self.inbox.count >= 4 + size else { break }
                    let payload = self.inbox.dropFirst(4).prefix(size)
                    guard let message = try? self.decoder.decode(LinkMessage.self, from: payload)
                    else { self.close(.invalidMessage); return }
                    self.inbox.removeFirst(4 + size)
                    self.lastReceived = ProcessInfo.processInfo.systemUptime
                    self.onMessage?(message)
                    if self.closed { return }
                }
            }
            if eof || error != nil { self.close(.transport) } else { self.receive() }
        }
    }

    func close(_ reason: LinkFailure = .transport) {
        guard !closed else { return }
        closed = true
        timer?.cancel()
        timer = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        let notify = onClose
        onReady = nil
        onMessage = nil
        onClose = nil
        notify?(reason)
    }
}
