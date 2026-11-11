import SwiftUI
import UIKit

// No account or production pairing. This throwaway app is simulator-only.
private let production = "https://temporary-nimble-spruce-dz8vszj.vercel.app"
private let testKey = String(repeating: "0", count: 64)

private func shortcut(_ text: String? = nil, returning stage: String? = nil) {
    var url = URLComponents()
    url.scheme = "shortcuts"
    url.host = stage == nil ? "run-shortcut" : "x-callback-url"
    if stage != nil { url.path = "/run-shortcut" }
    url.queryItems = [URLQueryItem(name: "name", value: "ShagAttack")]
    if let text {
        url.queryItems! += [URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: text)]
    }
    if let stage {
        let nonce = UUID().uuidString
        UserDefaults.standard.set(nonce, forKey: "pending-" + stage)
        for state in ["success", "cancel", "error"] {
            let reply = "shortlab-check://reply/" + stage + "/" + nonce + "/" + state
            url.queryItems!.append(URLQueryItem(name: "x-" + state, value: reply))
        }
    }
    if let target = url.url { UIApplication.shared.open(target) }
}

// Only the new simulator's pending request can produce this receipt.
// Never display the returned URL, personal data or unfiltered system errors.
private func receipt(for url: URL) -> String? {
    let parts = url.pathComponents
    guard url.scheme == "shortlab-check", url.host == "reply", parts.count == 4,
          ["direct", "pair"].contains(parts[1]), ["success", "cancel", "error"].contains(parts[3]),
          UserDefaults.standard.string(forKey: "pending-" + parts[1]) == parts[2] else { return nil }
    UserDefaults.standard.removeObject(forKey: "pending-" + parts[1])
    let prefix = "Native " + parts[1] + " " + parts[3]
    let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let message = fields.first { $0.name.lowercased() == "errormessage" }?.value ?? ""
    let result = fields.first { $0.name == "result" }?.value?.lowercased() ?? ""
    if result.contains("öffne mein tag in safari") { return prefix + " unpaired" }
    if result.contains("verbunden") { return prefix + " paired" }
    if parts[3] == "error" {
        let code = fields.first { $0.name.lowercased() == "errorcode" }?.value
        let number = code.flatMap(Int.init).map { " code " + String($0) } ?? ""
        let allowed = Set(("a an the is this that for of to in on at with not no can cannot could couldn t " +
            "was wasen were be been operation completed failed run running action shortcut shortcuts workflow " +
            "file files folder path found missing does exist exists unavailable available app application " +
            "installed service server runner connection connected invalid invalidated request denied allowed " +
            "permission interaction required account apple icloud drive device simulator access error domain " +
            "please select choose provide value input output parameter parameters argument arguments name " +
            "data type supported unsupported extension process execution stopped canceled cancelled user " +
            "unknown problem unexpected occurred communicate couldn’t successfully open read write save " +
            "must before using first time used upgrade update newer version contact developer couldn’t " +
            "internal anwendung aktion kurzbefehl datei ordner nicht gefunden konnte fehlgeschlagen").split(separator:" ").map(String.init))
        let words = message.replacingOccurrences(of:"+",with:" ").split(whereSeparator:{ !$0.isLetter && !$0.isNumber && $0 != "-" })
        let retained = words.prefix(65).map { token -> String in
            let word = String(token), lower = word.lowercased()
            if allowed.contains(lower) { return lower }
            if word.range(of:"^(?:NS|WF|IN|OS|VC|LN|FP|RBS|LS|Siri|AppIntents)[A-Za-z]{1,65}(?:Domain|Error|Action)$",options:.regularExpression) != nil { return word }
            if word.range(of:"^-?[0-9]{1,7}$",options:.regularExpression) != nil { return word }
            return "_"
        }
        let details = retained.isEmpty ? "no system message" : retained.joined(separator:" ")
        return prefix + number + " " + details
    }
    return prefix
}

@main struct Probe: App {
    @State private var lastReturn = ""
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
                if !lastReturn.isEmpty { Text(lastReturn).accessibilityIdentifier("nativeReceipt") }
                Button("Open public app") { UIApplication.shared.open(URL(string: production)!) }
                Button("Open published shortcut") {
                    UIApplication.shared.open(URL(string: production + "/shortcuts/ShagAttack.shortcut")!)
                }
                Button("Run exact name") { shortcut() }
                Button("Diagnose direct launch") {
                    lastReturn = ""
                    shortcut(returning: "direct")
                }
                Button("Share test appointment") { shortcut("Testtermin der Simulatorprobe morgen um 15 Uhr") }
                Button("Inspect installed shortcut") {
                    UIApplication.shared.open(URL(string: "shortcuts://open-shortcut?name=ShagAttack")!)
                }
                Button("Pair test simulator") {
                    lastReturn = ""
                    shortcut(production + "/?view=dashboard#mein-tag-diktat=1&key=" + testKey + "&id=[Zufallszahl]&at=[Datum]&text=[URL-codierter Text]", returning: "pair")
                }
                Button("Send test alarm") {
                    let at = Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 60) + 3) * 60)
                    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    shortcut(["MeinTag-Wecker", testKey, UUID().uuidString.lowercased(), iso.string(from: at), "Simulatorprobe"].joined(separator: "|"))
                }
            }.padding().onOpenURL { url in
                if let verified = receipt(for: url) { lastReturn = verified }
            }
        }
    }
}
