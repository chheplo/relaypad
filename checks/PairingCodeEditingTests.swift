import Foundation

@main
enum PairingCodeEditingTests {
    static func main() {
        func check(_ initial: String, _ location: Int, _ length: Int, _ replacement: String,
                   _ expected: String, _ caret: Int, selectionStart: Int? = nil) {
            let edit = PairingCodeEdit(display: initial, range: NSRange(location: location, length: length),
                                       replacement: replacement, selectionStart: selectionStart ?? location)
            precondition(edit?.text == expected && edit?.caret == caret,
                         "Incorrect text or caret for \(initial), \(location), \(length), \(replacement)")
        }

        check("ABC", 3, 0, "d", "ABCD-", 5)
        check("ABCD-EFG", 8, 0, "h", "ABCD-EFGH-", 10)
        check("", 0, 0, "abcDefghjkmn", "ABCD-EFGH-JKMN", 14)
        check("", 0, 0, "abcd-efgh-jkmn", "ABCD-EFGH-JKMN", 14)
        check("", 0, 0, " oi-l\n23456789abcd ", "0112-3456-789A", 14)
        check("ABCD-", 4, 1, "", "ABC", 3, selectionStart: 5)
        check("ABCD-EFGH-", 9, 1, "", "ABCD-EFG", 8, selectionStart: 10)
        check("ABCD-EFGH-JKMN", 5, 5, "", "ABCD-JKMN-", 5)
        check("ABCD-EFGH-JKMN", 3, 3, "xy", "ABCX-YFGH-JKMN", 6)
        check("ABCD-EFG", 4, 1, "", "ABCD-FG", 5)
        let full = "ABCD-EFGH-JKMN"
        precondition(PairingCodeEdit(display: full, range: NSRange(location: 4, length: 0),
                                     replacement: "9", selectionStart: 4) == nil)
        precondition(PairingCode.normalized(full) == "ABCDEFGHJKMN")
        print("Pairing code edit and validation checks passed.")
    }
}
