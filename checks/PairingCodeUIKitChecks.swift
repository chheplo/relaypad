import SwiftUI
import UIKit

@main
private struct PairingCheckApp: App {
    var body: some Scene { WindowGroup { PairingCheckScreen() } }
}

/// Exercise UIKit's paste pipeline using process-local item providers and the production field.
private struct PairingCheckScreen: View {
    @State private var text = ""
    @State private var focused = true

    var body: some View {
        PairingCodeField(text: $text, focused: $focused) {}
            .frame(height: 44)
            .task { await run() }
    }

    @MainActor private func run() async {
        var failures: [String] = []
        let name = ProcessInfo.processInfo.environment["RELAYPAD_CHECK_OUTPUT"] ?? "pairing-checks"
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            let result = failures.isEmpty ? "PASS" : failures.joined(separator: "\n")
            try? result.write(to: output, atomically: true, encoding: .utf8)
        }
        var field: PairingCodeField.Field?
        for _ in 0..<60 {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            field = windows.first(where: \.isKeyWindow).flatMap(findField)
            if field?.isFirstResponder == true { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let field, field.isFirstResponder else { failures.append("The field never received focus."); return }

        @MainActor func select(_ start: Int, length: Int) {
            guard let a = field.position(from: field.beginningOfDocument, offset: start),
                  let b = field.position(from: a, offset: length) else {
                failures.append("Could not select \(length) characters at \(start).")
                return
            }
            field.selectedTextRange = field.textRange(from: a, to: b)
        }
        @MainActor func paste(_ value: String, expecting expected: String) async {
            field.paste(itemProviders: [NSItemProvider(object: value as NSString)])
            for _ in 0..<50 {
                if field.text == expected { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            failures.append("Expected \(expected), got \(field.text ?? "nil").")
        }
        await paste("abcd-efgh-jkmn", expecting: "ABCD-EFGH-JKMN")
        select(0, length: field.text?.count ?? 0)
        await paste("oI-l23456789abc", expecting: "0112-3456-789A")
        select(3, length: 3)
        await paste("xy", expecting: "011X-Y456-789A")
        if let range = field.selectedTextRange {
            let caret = field.offset(from: field.beginningOfDocument, to: range.start)
            if !range.isEmpty || caret != 6 { failures.append("Expected insertion caret at 6, got \(caret).") }
        } else { failures.append("The insertion caret is missing.") }
        select(10, length: 0)
        field.deleteBackward()
        if text != "011X-Y457-89A" { failures.append("Backspace at separator did not update the code.") }
        select(0, length: field.text?.count ?? 0)
        await paste("abcdef", expecting: "ABCD-EF")
    }

    @MainActor private func findField(_ view: UIView) -> PairingCodeField.Field? {
        if let field = view as? PairingCodeField.Field { return field }
        return view.subviews.compactMap(findField).first
    }
}
