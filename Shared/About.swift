import Foundation
import SwiftUI

enum RelaypadAbout {
    static let developer = "Pratik Desai (@chheplo)"
    static let repository = URL(string: "https://github.com/chheplo/relaypad")!

    static var versionAndBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

struct AboutRows: View {
    var body: some View {
        LabeledContent("Version", value: RelaypadAbout.versionAndBuild)
        LabeledContent("Developer", value: RelaypadAbout.developer)
        Link(destination: RelaypadAbout.repository) {
            Label("GitHub project", systemImage: "arrow.up.right.square")
        }
        .accessibilityIdentifier("about.repository")
    }
}
