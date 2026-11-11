import XCTest

final class RoutingTests: XCTestCase {
    private let host = XCUIApplication()
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    private let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let siri = XCUIApplication(bundleIdentifier: "com.apple.SiriViewService")
    private var surfaces: [XCUIApplication] { [shortcuts, host, siri, spring] }

    private func visible(_ part: String, in apps: [XCUIApplication]) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", part)
        return apps.filter { $0.state == .runningForeground }.contains {
            $0.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.contains { $0.isHittable }
        }
    }
    @discardableResult private func tap(_ labels: [String], in apps: [XCUIApplication]) -> Bool {
        for app in apps where app.state == .runningForeground {
            for title in labels {
                let item = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch
                if item.exists && item.isHittable { item.tap(); return true }
            }
        }
        return false
    }
    private func until(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat { if condition() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.4)) } while Date() < end
        return false
    }
    private func action(_ title: String) { host.activate(); host.buttons[title].tap() }
    private func dismiss() { _ = tap(["Done","Fertig","OK"], in: surfaces) }
    private func evidence(_ message: String) { print("SIMULATOR_EVIDENCE " + message) }

    private func screen(_ stage: String) {
        // Only labels from a fresh, signed-out simulator. Never include URLs or pairing strings.
        for (name, app) in [("Files", files), ("Shortcuts", shortcuts), ("Safari", safari), ("Siri", siri), ("Probe", host), ("Home", spring)]
            where app.state == .runningForeground {
            let labels = app.debugDescription.components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    guard let marker = line.range(of: "label: '") else { return nil }
                    let label = String(line[marker.upperBound...].prefix(while: { $0 != "'" }))
                    guard label.count < 140, !label.contains("://"), !label.contains("@"),
                          label.range(of:"[a-f0-9]{32,}",options:.regularExpression) == nil else { return nil }
                    return label
                }
            print("SIMULATOR_SCREEN \(stage) \(name) \(labels.prefix(45).joined(separator: " | "))")
        }
    }

    private func tapFileItem(_ name: String, in app: XCUIApplication) -> Bool {
        guard app.state == .runningForeground else { return false }
        let match = NSPredicate(format: "label CONTAINS[c] %@", name)
        for type in [XCUIElement.ElementType.cell, .button, .link, .staticText] {
            let item = app.descendants(matching:type).matching(match).firstMatch
            if item.exists && item.isHittable { item.tap(); return true }
        }
        return false
    }

    private func acceptImport() -> Bool {
        if tap(["Add Shortcut","Kurzbefehl hinzufügen"], in:[shortcuts,files,safari]) { return true }
        return visible("ShagAttack",in:[shortcuts]) && tap(["Add","Hinzufügen"],in:[shortcuts])
    }

    private func importFromDownload() -> Bool {
        action("Open published shortcut")
        var downloaded = false, openedList = false, openedFile = false, openedMenu = false
        let added = until(18) {
            if self.acceptImport() { return true }
            if !downloaded && self.tap(["Download","Laden","Herunterladen"],in:[self.safari]) {
                downloaded = true
            } else if downloaded && !openedList && self.tap(["Downloads","Show Downloads","Downloads anzeigen"],in:[self.safari]) {
                openedList = true
            } else if downloaded && !openedList && !openedMenu && self.tap(["Page Menu","Seitenmenü"],in:[self.safari]) {
                openedMenu = true
            } else if openedList && !openedFile && self.tapFileItem("ShagAttack",in:self.safari) {
                openedFile = true
            }
            return false
        }
        if downloaded { evidence("safari_download_accepted") }
        if !added { screen("download") }
        return added
    }

    private func importFromFiles() -> Bool {
        guard SystemApps.hasFiles else { return false }
        files.launch()
        _ = tap(["Continue","Weiter"],in:[files])
        if !tapFileItem("ShagAttack",in:files) {
            _ = tap(["Browse","Durchsuchen"],in:[files])
            let local = until(8) { self.tapFileItem("On My iPhone",in:self.files) || self.tapFileItem("Auf meinem iPhone",in:self.files) }
            guard local else { screen("files_locations"); return false }
            let folder = until(8) { self.tapFileItem("Shortcut Lab",in:self.files) }
            guard folder else { screen("files_folders"); return false }
            let selected = until(8) { self.tapFileItem("ShagAttack",in:self.files) }
            guard selected else { screen("files_documents"); return false }
        }
        evidence("signed_file_opened_from_files")
        let confirmed = until(15) { self.acceptImport() }
        if !confirmed { screen("file_opened") }
        return confirmed
    }

    func testPublishedAppOpensInSafari() {
        host.launch(); action("Open public app")
        let loaded = until(30) {
            self.safari.state == .runningForeground && self.safari.webViews.firstMatch.exists &&
            (self.visible("anmelden", in:[self.safari]) || self.visible("E-Mail", in:[self.safari]))
        }
        XCTAssertTrue(loaded, "The public account-free sign-in page was not observed in simulated Safari.")
        if loaded { evidence("public_web_app_opened_in_simulated_safari") }
    }

    func testSignedShortcutRoutingAndClock() throws {
        host.launch()
        shortcuts.launch()
        _ = tap(["Continue","Weiter","Get Started","Not Now","Nicht jetzt"],in:[shortcuts])
        let added = importFromDownload() || importFromFiles()
        if added { evidence("signed_shortcut_add_confirmed") }

        let unpaired = "Öffne Mein Tag in Safari"
        action("Run exact name")
        guard until(25,{self.visible(unpaired,in:self.surfaces)}) else {
            screen("named_launch")
            XCTFail("The workflow-specific direct-start message was not observed after the import attempt."); return
        }
        evidence("named_direct_start_reached_actual_workflow")
        dismiss(); shortcuts.terminate(); host.activate(); XCUIDevice.shared.press(.home)
        guard !visible(unpaired,in:surfaces) else { XCTFail("Stale prior result prevents a valid Siri assertion."); return }
        // Apple supplies recognized text. This does NOT use the user's voice or microphone.
        XCUIDevice.shared.siriService.activate(voiceRecognitionText:"ShagAttack")
        if until(25,{self.visible(unpaired,in:self.surfaces)}) { evidence("siri_recognized_text_routed_to_exact_workflow") }
        else { screen("siri_result"); XCTFail("Siri did not produce the workflow-specific result for the recognized text ShagAttack.") }
        dismiss(); host.activate(); action("Pair test simulator")
        guard until(25,{
            if self.visible("Verbunden. Sage Siri",in:self.surfaces) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],in:[self.shortcuts]);return false
        }) else { screen("pairing_result"); XCTFail("The disposable pairing file could not be saved; Clock is untested.");return }
        evidence("synthetic_simulator_pairing_acknowledged"); dismiss()
        guard let clockID = SystemApps.clock else { evidence("clock_unavailable_in_runtime"); return }
        action("Send test alarm")
        guard until(25,{
            if self.visible("Schlummern ist eingeschaltet",in:self.surfaces) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],in:[self.shortcuts]);return false
        }) else { XCTFail("Shortcut did not acknowledge the Clock action.");return }
        dismiss()
        let clock = XCUIApplication(bundleIdentifier:clockID)
        clock.launch(); _ = tap(["Alarm","Alarms","Wecker"],in:[clock])
        let exists = until(15,{self.visible("Simulatorprobe",in:[clock])})
        XCTAssertTrue(exists,"The named test alarm was not observed in Apple's Clock app.")
        if exists { evidence("named_alarm_observed_in_simulated_clock_no_sound_or_physical_snooze_claim") }
    }
}
