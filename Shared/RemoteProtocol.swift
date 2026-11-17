import Foundation

enum RemoteButton: String, Codable {
    case left, right, middle
}

enum RemoteEvent: Codable, Equatable {
    case move(dx: Double, dy: Double)
    case scroll(dx: Double, dy: Double)
    case button(button: RemoteButton, down: Bool)
    case click(button: RemoteButton, count: Int)
    case key(code: UInt16, down: Bool)
    case text(String)
    case releaseAll

    var isValid: Bool {
        switch self {
        case let .move(x, y), let .scroll(x, y):
            return x.isFinite && y.isFinite && abs(x) <= 65_536 && abs(y) <= 65_536
        case let .click(_, count):
            return (1...2).contains(count)
        case let .key(code, _):
            return code <= 127
        case let .text(value):
            return value.utf8.count <= 16_384
        case .button, .releaseAll:
            return true
        }
    }
}

enum LinkMessage: Codable {
    case hello(version: Int, name: String)
    case ready(canControl: Bool)
    case input(RemoteEvent)
    case heartbeat
    case busy
}

enum PairingCode {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alphabet.randomElement(using: &rng)! })
    }

    static func canonicalSymbols(in value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace && $0 != "-" }
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
    }

    static func normalized(_ value: String) -> String? {
        let code = canonicalSymbols(in: value)
        guard code.count == 12, code.allSatisfy(alphabet.contains) else { return nil }
        return code
    }

    static func display(_ value: String) -> String {
        [value.prefix(4), value.dropFirst(4).prefix(4), value.suffix(4)].joined(separator: "-")
    }
}
