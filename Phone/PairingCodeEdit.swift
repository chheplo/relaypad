import Foundation

/// UITextField uses offsets in the displayed string. Apply edits to the underlying symbols so
/// deleting a separator also removes a character and mid-string replacements preserve the suffix.
struct PairingCodeEdit {
    let text: String
    let caret: Int

    init?(display: String, range: NSRange, replacement: String, selectionStart: Int) {
        let old = Array(display)
        let start = min(range.location, old.count)
        let end = min(start + range.length, old.count)
        var digits = old.filter { $0 != "-" }
        var first = old[..<start].filter { $0 != "-" }.count
        var last = first + old[start..<end].filter { $0 != "-" }.count

        if replacement.isEmpty, start < end, first == last {
            if start == selectionStart, last < digits.count {
                last += 1   // Forward deletion at a separator.
            } else if first > 0 {
                first -= 1  // Backspace just after a separator.
            }
        }
        let room = 12 - (digits.count - (last - first))
        let added = PairingCode.canonicalSymbols(in: replacement)
            .filter(PairingCode.alphabet.contains)
            .prefix(max(0, room))
        if !replacement.isEmpty && added.isEmpty { return nil }
        digits.replaceSubrange(first..<last, with: added)
        var displayText = ""
        for (index, character) in digits.enumerated() {
            displayText.append(character)
            if index == 3 || index == 7 { displayText.append("-") }
        }
        text = displayText
        let symbolPosition = first + added.count
        caret = symbolPosition + (symbolPosition >= 4 ? 1 : 0) + (symbolPosition >= 8 ? 1 : 0)
    }
}
