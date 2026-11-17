import Foundation
import SwiftUI

enum RelaypadAbout {
    static let developer = "Pratik Desai (@chheplo)"
    static let repository = URL(string: "https://github.com/chheplo/relaypad")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

struct AboutRows: View {
    var body: some View {
        LabeledContent("Version", value: RelaypadAbout.version)
            .accessibilityIdentifier("about.version")
        LabeledContent("Developer", value: RelaypadAbout.developer)
        Link(destination: RelaypadAbout.repository) {
            Label("GitHub project", systemImage: "arrow.up.right.square")
        }
        .accessibilityIdentifier("about.repository")
    }
}
