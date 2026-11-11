import SwiftUI
import UIKit

// No account or production pairing. This throwaway app is simulator-only.
private let production = "https://temporary-nimble-spruce-dz8vszj.vercel.app"
private let testKey = String(repeating: "0", count: 64)

private func shortcut(_ text: String? = nil) {
    var url = URLComponents()
    url.scheme = "shortcuts"; url.host = "run-shortcut"
    url.queryItems = [URLQueryItem(name: "name", value: "ShagAttack")]
    if let text {
        url.queryItems! += [URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: text)]
    }
    if let target = url.url { UIApplication.shared.open(target) }
}

@main struct Probe: App {
    init() {
        // Files exposes this copy under On My iPhone. The signed bytes stay intact.
        if let source = Bundle.main.url(forResource: "ShagAttack", withExtension: "shortcut"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let copy = documents.appendingPathComponent(source.lastPathComponent)
            if !FileManager.default.fileExists(atPath: copy.path) {
                try? FileManager.default.copyItem(at: source, to: copy)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Button("Open public app") { UIApplication.shared.open(URL(string: production)!) }
                Button("Open published shortcut") {
                    UIApplication.shared.open(URL(string: production + "/shortcuts/ShagAttack.shortcut")!)
                }
                Button("Run exact name") { shortcut() }
                Button("Pair test simulator") {
                    shortcut(production + "/?view=dashboard#mein-tag-diktat=1&key=" + testKey + "&id=[Zufallszahl]&at=[Datum]&text=[URL-codierter Text]")
                }
                Button("Send test alarm") {
                    let at = Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 60) + 3) * 60)
                    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    shortcut(["MeinTag-Wecker", testKey, UUID().uuidString.lowercased(), iso.string(from: at), "Simulatorprobe"].joined(separator: "|"))
                }
            }.padding()
        }
    }
}
