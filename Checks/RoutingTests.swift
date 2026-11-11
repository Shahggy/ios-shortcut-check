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
        if contains("Welcome",initial) || contains("Willkommen",initial) || contains("New in Shortcuts",initial) || contains("Neu in Kurzbefehle",initial) {
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
        return observe(inSafari ? "safari_import" : "files_import", seconds:inSafari ? 50 : 85) { screen in
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
                // After entering the folder, Files briefly keeps the same labels in its
                // toolbar. Tapping that toolbar opens the folder menu, not the document.
                if taken.contains("folder") && !self.contains("ShagAttack",screen) { return false }
                // Tapping a file's filename in grid view starts renaming. Tap its document icon.
                if self.contains("ShagAttack",screen) && once("documentIcon",["SHORTCUT"]) {
                    self.evidence("tapped_signed_document_icon_in_files")
                    return false
                }
                if !taken.contains("documentIcon") && self.contains("ShagAttack",screen) {
                    if let filename = screen.first(where: {
                        self.folded($0.label).hasPrefix("shagattack") && $0.box.midY < 0.85
                    }) {
                        taken.insert("documentIcon")
                        // Both previous observed Files screens placed the icon 0.04 above its label.
                        front.coordinate(withNormalizedOffset:CGVector(dx:filename.box.midX,dy:1-filename.box.midY-0.04)).tap()
                        return false
                    }
                }
                if once("folder",["Shortcut Lab","Probe"],prefix:true) { return false }
                if (self.contains("Locations",screen) || self.contains("Speicherorte",screen)) &&
                    once("local",["On My iPhone","Auf meinem iPhone"],prefix:true) { return false }
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

    // Production pairing already uses Apple's x-callback-url. A missing
    // screen message and an explicit failure callback are distinct results.
    private func callbackResult(_ stage: String, seconds: TimeInterval) -> (receipt: String?, workflowMessage: Bool) {
        var receipt: String?
        var workflowMessage = false
        _ = observe(stage + "_callback",seconds:seconds) { screen in
            if self.host.state == .runningForeground {
                let field = self.host.staticTexts["nativeReceipt"]
                if field.exists && field.label.hasPrefix("Native " + stage + " ") {
                    receipt = field.label
                    self.evidence(field.label)
                    return true
                }
            }
            let message = stage == "pair" ? "Verbunden Sage Siri" : self.unpaired
            if self.contains(message,screen) {
                workflowMessage = true
                _ = self.tap(["Done","Fertig","OK"],on:self.shortcuts,screen:screen)
            } else if stage == "pair" {
                _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],on:self.shortcuts,screen:screen)
            }
            return false
        }
        return (receipt, workflowMessage)
    }

    func testPublishedAppOpensInSafari() {
        host.launch()
        action("Open public app")
        defer { safari.terminate() }
        let loaded = observe("public_safari",seconds:50) {
            self.safari.state == .runningForeground &&
            (self.contains("Dein Tag auf allen", $0) || self.contains("Danach direkt loslegen", $0) || (self.contains("Aufgaben und Termine an einem Ort", $0) && self.contains("App Passwort", $0)))
        }
        XCTAssertTrue(loaded,"The rendered application sign-in screen was not observed.")
        if loaded { evidence("public_web_app_opened_in_simulated_safari") }
    }

    func testShortcutFileImportAndDirectStart() {
        host.launch()
        prepareLibrary()
        let observedImport = importFile(inSafari:false)
        if !observedImport {
            _ = importFile(inSafari:true)
        }
        if directResult() {
            evidence("named_direct_start_reached_actual_workflow")
            return
        }
        action("Diagnose direct launch")
        let result = callbackResult("direct",seconds:22)
        let verified = result.workflowMessage || result.receipt == "Native direct success unpaired"
        if verified { evidence("named_direct_start_reached_actual_workflow") }
        XCTAssertTrue(verified, "Unpaired workflow output was not observed. Callback: " + (result.receipt ?? "none"))
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
        let result = callbackResult("pair",seconds:32)
        guard result.receipt?.hasPrefix("Native pair success") == true else {
            XCTFail("The pairing callback did not succeed. Workflow message: " + String(result.workflowMessage) + ". Callback: " + (result.receipt ?? "none"))
            return
        }
        evidence("native_pair_success_callback_observed")
        if result.workflowMessage || result.receipt == "Native pair success paired" {
            evidence("synthetic_simulator_pairing_acknowledged")
        }
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

    // A single fresh-device session: prove the install before requesting any
    // callback. An empty library makes pairing diagnostics uninformative.
    func testInstalledWorkflowPairing() {
        host.launch()
        prepareLibrary()
        guard importFile(inSafari:false) else { XCTFail("No verified native import. Pairing was not attempted."); return }
        let installed = observe("installed_library",seconds:22) { screen in
            guard self.shortcuts.state == .runningForeground else { return false }
            if self.tap(["Add Shortcut","Kurzbefehl hinzufügen"],on:self.shortcuts,screen:screen) { return false }
            let library = self.contains("All Shortcuts",screen) || self.contains("Alle Kurzbefehle",screen)
            return library && self.contains("ShagAttack",screen)
        }
        guard installed else { XCTFail("The named shortcut was not visible in the collection."); return }
        evidence("named_shortcut_visible_in_apple_library_before_pair")
        action("Pair test simulator")
        let result = callbackResult("pair",seconds:40)
        if let reply = result.receipt, reply.hasPrefix("Native pair error") {
            action("Inspect installed shortcut")
            var edited = false
            _ = observe("editor_after_pair_error",seconds:15) { screen in
                if self.contains("unknown action",screen) || self.contains("app not installed",screen) {
                    self.evidence("editor_reports_unavailable_action")
                    return true
                }
                if !edited && self.tap(["Edit","Bearbeiten"],on:self.shortcuts,screen:screen) { edited = true }
                return self.contains("Current Date",screen) && self.contains("Text",screen)
            }
            XCTFail("Installed shortcut rejected the pairing request. " + reply)
            return
        }
        if result.receipt?.hasPrefix("Native pair success") == true {
            evidence("native_pair_success_callback_observed")
        }
        if result.workflowMessage || result.receipt == "Native pair success paired" {
            evidence("synthetic_simulator_pairing_acknowledged")
        }
        // Only the configured workflow can turn this harmless shared text
        // into a Safari handoff. No production account exists on this device.
        action("Share test appointment")
        let opened = observe("shared_appointment",seconds:50) { screen in
            if self.safari.state == .runningForeground && self.contains("Aufgaben und Termine an einem Ort",screen) {
                return true
            }
            if self.shortcuts.state == .runningForeground {
                if self.contains("open", screen) || self.contains("allow", screen) {
                    _ = self.tap(["Allow Once","Allow","Open","Einmal erlauben","Öffnen"],on:self.shortcuts,screen:screen)
                }
            }
            return false
        }
        if opened { evidence("paired_native_share_reached_public_login_without_account") }
        XCTAssertTrue(opened, "No task handoff observed from the installed workflow.")
        XCTAssertTrue(result.receipt?.hasPrefix("Native pair success") == true, "Pairing callback: " + (result.receipt ?? "none"))
    }
}
