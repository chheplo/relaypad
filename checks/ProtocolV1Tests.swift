import Foundation
import Network
import Security

@main
struct ProtocolV1Tests {
    static func main() throws {
        let fixtures: [(LinkMessage, String)] = [
            (.hello(version: 1, name: "iPhone"), #"{"hello":{"name":"iPhone","version":1}}"#),
            (.ready(canControl: false), #"{"ready":{"canControl":false}}"#),
            (.ready(canControl: true), #"{"ready":{"canControl":true}}"#),
            (.busy, #"{"busy":{}}"#),
            (.heartbeat, #"{"heartbeat":{}}"#),
            (.input(.move(dx: -1.5, dy: 3)), #"{"input":{"_0":{"move":{"dx":-1.5,"dy":3}}}}"#),
            (.input(.scroll(dx: 8, dy: -2)), #"{"input":{"_0":{"scroll":{"dx":8,"dy":-2}}}}"#),
            (.input(.button(button: .middle, down: false)), #"{"input":{"_0":{"button":{"down":false,"button":"middle"}}}}"#),
            (.input(.click(button: .left, count: 1)), #"{"input":{"_0":{"click":{"count":1,"button":"left"}}}}"#),
            (.input(.click(button: .right, count: 2)), #"{"input":{"_0":{"click":{"count":2,"button":"right"}}}}"#),
            (.input(.key(code: 63, down: true)), #"{"input":{"_0":{"key":{"down":true,"code":63}}}}"#),
            (.input(.key(code: 63, down: false)), #"{"input":{"_0":{"key":{"code":63,"down":false}}}}"#),
            (.input(.text("Hello 👋")), #"{"input":{"_0":{"text":{"_0":"Hello 👋"}}}}"#),
            (.input(.releaseAll), #"{"input":{"_0":{"releaseAll":{}}}}"#)
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for (message, frozenJSON) in fixtures {
            let original = Data(frozenJSON.utf8)
            let decoded = try decoder.decode(LinkMessage.self, from: original)
            let expected = try JSONSerialization.jsonObject(with: original) as! NSDictionary
            for value in [message, decoded] {
                let wire = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! NSDictionary
                require(wire == expected, "v1 payload changed: " + frozenJSON)
            }
        }
        require(LocalService.type == "_relaypad._tcp" && LocalService.version == 1, "v1 discovery or version changed")
        require(PairingCode.normalized("oI23-4567-89ab") == "0123456789AB", "Pairing code normalization changed")
        try checkEncryptedFrames()
        print("Passed \(fixtures.count) v1 payload fixtures and the encrypted wire check.")
    }

    // An independent peer uses a fixed, public test vector and v1 bytes. It never advertises Bonjour.
    static func checkEncryptedFrames() throws {
        let listenerParameters = LocalService.parameters(code: "0123456789AB")
        listenerParameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: listenerParameters)
        var server: SecureChannel?
        var messages = [String]()
        listener.newConnectionHandler = { connection in
            let channel = SecureChannel(connection)
            server = channel
            channel.onMessage = { message in
                switch message {
                case .hello(version: 1, name: "iPhone"): messages.append("hello")
                case .input(.key(code: 63, down: true)): messages.append("fn")
                default: require(false, "Unexpected message from the v1 fixture")
                }
            }
            channel.onReady = { [weak channel] in channel?.send(.busy) }
            channel.start()
        }
        var isListening = false
        listener.stateUpdateHandler = { state in
            if case .ready = state { isListening = true }
            if case .failed(let error) = state { require(false, error.localizedDescription) }
        }
        listener.start(queue: .main)
        defer { listener.cancel(); server?.close() }
        wait(for: "loopback listener") { isListening }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0x00a8)!)
        let psk: [UInt8] = [
            0x54, 0x1e, 0x42, 0x99, 0x6a, 0x91, 0xc5, 0x61, 0x57, 0x04, 0x9b, 0xa1, 0xe8, 0xda, 0x4f, 0x72,
            0x5e, 0xe7, 0x1d, 0xdb, 0xfa, 0x5f, 0x23, 0x5a, 0x9f, 0xe9, 0xa0, 0x1f, 0x1d, 0xbd, 0x4f, 0xc2
        ]
        let key = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Array("Relaypad-1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)

        let client = NWConnection(host: "127.0.0.1", port: listener.port!,
                                  using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        defer { client.cancel() }
        let busy = Data([0, 0, 0, 11]) + Data(#"{"busy":{}}"#.utf8)
        var receivedBusy = false
        client.stateUpdateHandler = { state in
            if case .failed(let error) = state { require(false, error.localizedDescription) }
        }
        client.start(queue: .main)
        client.receive(minimumIncompleteLength: busy.count, maximumLength: busy.count) { bytes, _, _, _ in
            require(bytes == busy, "Outbound v1 framing changed")
            receivedBusy = true
        }
        let hello = Data([0, 0, 0, 39]) + Data(#"{"hello":{"version":1,"name":"iPhone"}}"#.utf8)
        let keyDown = Data([0, 0, 0, 48]) + Data(#"{"input":{"_0":{"key":{"down":true,"code":63}}}}"#.utf8)
        // Split the first length field and send the next complete message with the remainder.
        client.send(content: hello.prefix(2), completion: .contentProcessed { error in
            require(error == nil, "Could not send first fragment")
            client.send(content: hello.dropFirst(2) + keyDown, completion: .contentProcessed { error in
                require(error == nil, "Could not send v1 messages")
            })
        })
        wait(for: "v1 frame exchange") { receivedBusy && messages == ["hello", "fn"] }
    }

    static func wait(for label: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        require(condition(), "Timed out waiting for " + label)
    }

    static func require(_ condition: Bool, _ message: String) {
        if !condition {
            FileHandle.standardError.write(Data(("FAILED: " + message + "\n").utf8))
            exit(1)
        }
    }
}
