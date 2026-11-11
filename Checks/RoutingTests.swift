import XCTest
import Vision

final class RoutingTests: XCTestCase {
    private let host = XCUIApplication()
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    private let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let siri = XCUIApplication(bundleIdentifier: "com.apple.SiriViewService")
    private let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let unpaired = "öffne mein tag in safari"
    private var lastScreen = ""

    private struct Line {
        let label: String
        let box: CGRect
    }

    private func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    // Reading the rendered screen also works when Safari's accessibility tree stalls.
    private func lines(_ stage: String) -> [Line] {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        if let supported = try? request.supportedRecognitionLanguages() {
            let languages = ["en-US", "de-DE"].filter { supported.contains($0) }
            if !languages.isEmpty { request.recognitionLanguages = languages }
        }
        do { try VNImageRequestHandler(cgImage:image,options:[:]).perform([request]) }
        catch { print("SIMULATOR_SCREEN \(stage) OCR unavailable"); return [] }
        let result = (request.results ?? []).compactMap { observed -> Line? in
            guard let label = observed.topCandidates(1).first?.string else { return nil }
            return Line(label: label, box: observed.boundingBox)
        }.sorted { $0.box.midY > $1.box.midY }
        let publicLabels = result.map(\.label).filter {
            $0.count < 120 && !$0.contains("@") && !$0.contains("://") && !$0.contains("&key=") &&
                $0.range(of: "[A-Fa-f0-9]{32,}", options: .regularExpression) == nil
        }
        let summary = stage + " " + publicLabels.prefix(32).joined(separator: " | ")
        if summary != lastScreen { print("SIMULATOR_SCREEN " + summary); lastScreen = summary }
        return result
    }

    private func contains(_ part: String, _ screen: [Line]) -> Bool {
        folded(screen.map(\.label).joined(separator:" ")).contains(folded(part))
    }

    // Interact only with labels actually observed on the empty simulator.
    @discardableResult private func tap(_ names: [String], on app: XCUIApplication,
                                        screen: [Line], prefix: Bool = false) -> Bool {
        guard app.state == .runningForeground else { return false }
        for name in names {
            let wanted = folded(name)
            guard let item = screen.last(where: {
                let actual = folded($0.label)
                return actual == wanted || (prefix && actual.hasPrefix(wanted + " "))
            }) else { continue }
            app.coordinate(withNormalizedOffset: CGVector(dx:item.box.midX,dy:1-item.box.midY)).tap()
            return true
        }
        return false
    }

    private func observe(_ stage: String, seconds: TimeInterval,
                         _ handler: ([Line]) -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if handler(lines(stage)) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        } while Date() < end
        return false
    }

    private func action(_ title: String) {
        host.activate()
        host.buttons[title].tap()
    }

    private func evidence(_ text: String) { print("SIMULATOR_EVIDENCE " + text) }

    private func prepareLibrary() {
        shortcuts.launch()
        let initial = lines("shortcuts_library")
        if contains("Welcome",initial) || contains("Willkommen",initial) {
            tap(["Continue","Weiter","Get Started"],on:shortcuts,screen:initial)
        }
    }

    // Prefer the verified copy in the normal Files app. Try Safari's download
    // separately if this runtime cannot present the Files import sheet.
    private func importFile(inSafari: Bool) -> Bool {
        if inSafari { action("Open published shortcut") }
        else if SystemApps.hasFiles { files.launch() }
        else { return false }
        var taken = Set<String>()
        return observe(inSafari ? "safari_import" : "files_import", seconds:50) { screen in
            guard let front = [self.shortcuts,self.files,self.safari,self.home].first(where: { $0.state == .runningForeground }) else { return false }
            func once(_ key: String, _ names: [String], prefix: Bool = false) -> Bool {
                guard !taken.contains(key), self.tap(names,on:front,screen:screen,prefix:prefix) else { return false }
                taken.insert(key)
                return true
            }
            if self.tap(["Add Shortcut","Kurzbefehl hinzufügen","Add to Shortcuts"],on:front,screen:screen) {
                self.evidence("signed_shortcut_add_confirmed")
                return true
            }
            if front === self.shortcuts && self.contains("ShagAttack",screen) {
                if self.tap(["Add","Hinzufügen"],on:front,screen:screen) {
                    self.evidence("signed_shortcut_add_confirmed")
                }
                // The next assertion requires the unique output from the actual workflow.
                return true
            }
            if front === self.files {
                if once("file",["ShagAttack","ShagAttack.shortcut"],prefix:true) { return false }
                if once("folder",["Shortcut Lab","Probe"],prefix:true) { return false }
                if once("local",["On My iPhone","Auf meinem iPhone"],prefix:true) { return false }
                if once("browse",["Browse","Durchsuchen"]) { return false }
                if once("fileWelcome",["Continue","Weiter"]) { return false }
                _ = once("openWith",["Open in Shortcuts","In Kurzbefehle öffnen","Open With","Öffnen mit","Shortcuts","Kurzbefehle"])
            } else if front === self.safari {
                if once("download",["Download","Laden","Herunterladen","View","Anzeigen"]) { return false }
                if once("downloads",["Downloads","Show Downloads","Downloads anzeigen"]) { return false }
                if once("openFile",["ShagAttack.shortcut","ShagAttack"],prefix:true) { return false }
                _ = once("pageMenu",["Page Menu","Seitenmenü"])
            } else if self.contains("Shortcuts",screen) || self.contains("ShagAttack",screen) {
                _ = once("open",["Open","Öffnen","Continue","Weiter"])
            }
            return false
        }
    }

    private func directResult() -> Bool {
        action("Run exact name")
        return observe("direct",seconds:15) { self.contains(self.unpaired,$0) }
    }

    func testPublishedAppOpensInSafari() {
        host.launch()
        action("Open public app")
        defer { safari.terminate() }
        let loaded = observe("public_safari",seconds:50) {
            self.safari.state == .runningForeground &&
            (self.contains("Dein Tag auf allen", $0) || self.contains("Danach direkt loslegen", $0))
        }
        XCTAssertTrue(loaded,"The rendered application sign-in screen was not observed.")
        if loaded { evidence("public_web_app_opened_in_simulated_safari") }
    }

    func testShortcutFileImportAndDirectStart() {
        host.launch()
        prepareLibrary()
        _ = importFile(inSafari:false)
        var direct = directResult()
        if !direct {
            _ = importFile(inSafari:true)
            direct = directResult()
        }
        XCTAssertTrue(direct,"The direct launch did not produce the specific unpaired-workflow message.")
        if direct { evidence("named_direct_start_reached_actual_workflow") }
    }

    // The suite records Siri's own response even if the import test failed.
    func testSiriRecognizedName() {
        shortcuts.terminate()
        host.launch()
        XCUIDevice.shared.press(.home)
        guard !contains(unpaired,lines("before_siri")) else { XCTFail("Stale result before the Siri call."); return }
        evidence("siri_name_request_attempted")
        XCUIDevice.shared.siriService.activate(voiceRecognitionText:"ShagAttack")
        let routed = observe("siri",seconds:25) { self.contains(self.unpaired,$0) }
        if routed { evidence("siri_recognized_text_routed_to_exact_workflow") }
        else { XCTFail("Siri did not show the workflow-specific result for the recognized name.") }
    }

    func testSyntheticPairAndClock() {
        host.launch()
        action("Pair test simulator")
        let paired = observe("pair",seconds:25) {
            if self.contains("Verbunden Sage Siri",$0) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],on:self.shortcuts,screen:$0)
            return false
        }
        guard paired else { XCTFail("No pairing acknowledgement from the actual shortcut."); return }
        evidence("synthetic_simulator_pairing_acknowledged")
        guard let clockID = SystemApps.clock else { evidence("clock_unavailable_in_runtime"); return }
        action("Send test alarm")
        let sent = observe("alarm",seconds:25) {
            if self.contains("Schlummern ist eingeschaltet",$0) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],on:self.shortcuts,screen:$0)
            return false
        }
        guard sent else { XCTFail("No Clock acknowledgement."); return }
        let clock = XCUIApplication(bundleIdentifier:clockID)
        clock.launch()
        let found = observe("clock",seconds:18) {
            if self.contains("Simulatorprobe",$0) { return true }
            _ = self.tap(["Alarms","Alarm","Wecker"],on:clock,screen:$0)
            return false
        }
        XCTAssertTrue(found,"The named alarm was not visible in Clock.")
        if found { evidence("named_alarm_observed_in_simulated_clock_no_sound_or_physical_snooze_claim") }
    }
}
