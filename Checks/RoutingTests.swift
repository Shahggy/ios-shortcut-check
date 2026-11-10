import XCTest

final class RoutingTests: XCTestCase {
    private let host = XCUIApplication()
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    private let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private var surfaces: [XCUIApplication] { [shortcuts, host, spring] }

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
        // Each run gets a newly created, empty simulator. Never target a personal device.
        host.launch()
        let install = host.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "Import test shortcut")).firstMatch
        XCTAssertTrue(install.waitForExistence(timeout:8)); install.tap()
        // Use the public share/import sheet, not Shortcuts' internal database.
        let offer = ["Shortcuts","Kurzbefehle","Open in Shortcuts","In Kurzbefehle öffnen","More","Mehr"]
        let add = ["Add Shortcut","Kurzbefehl hinzufügen","Add","Hinzufügen"]
        var added = false
        _ = until(35) {
            if self.tap(add,in:[self.shortcuts]) { added=true; return true }
            _ = self.tap(offer,in:self.surfaces); return false
        }
        guard added else { XCTFail("Apple did not expose the signed-file import confirmation. Installation is unverified."); return }
        evidence("signed_shortcut_add_confirmed")

        let unpaired = "Öffne Mein Tag in Safari"
        action("Run exact name")
        guard until(25,{self.visible(unpaired,in:self.surfaces)}) else {
            XCTFail("Opening the URL scheme alone is not proof: the unique unpaired message was not observed."); return
        }
        evidence("named_direct_start_reached_actual_workflow")
        dismiss(); shortcuts.terminate(); host.activate(); XCUIDevice.shared.press(.home)
        guard !visible(unpaired,in:surfaces) else { XCTFail("Stale prior result prevents a valid Siri assertion."); return }
        // Apple supplies recognized text. This does NOT use the user's voice or microphone.
        XCUIDevice.shared.siriService.activate(voiceRecognitionText:"ShagAttack")
        if until(25,{self.visible(unpaired,in:self.surfaces)}) { evidence("siri_recognized_text_routed_to_exact_workflow") }
        else { XCTFail("Siri did not produce the workflow-specific result for the recognized text ShagAttack.") }
        dismiss(); host.activate(); action("Pair test simulator")
        guard until(25,{
            if self.visible("Verbunden. Sage Siri",in:self.surfaces) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],in:[self.shortcuts]);return false
        }) else { XCTFail("The disposable pairing file could not be saved; Clock is untested.");return }
        evidence("synthetic_simulator_pairing_acknowledged"); dismiss(); action("Send test alarm")
        guard until(25,{
            if self.visible("Schlummern ist eingeschaltet",in:self.surfaces) { return true }
            _ = self.tap(["Allow Once","Einmal erlauben","Allow","Erlauben"],in:[self.shortcuts]);return false
        }) else { XCTFail("Shortcut did not acknowledge the Clock action.");return }
        dismiss()
        let clock = XCUIApplication(bundleIdentifier:"com.apple.mobiletimer")
        clock.launch(); _ = tap(["Alarm","Alarms","Wecker"],in:[clock])
        let exists = until(15,{self.visible("Simulatorprobe",in:[clock])})
        XCTAssertTrue(exists,"The named test alarm was not observed in Apple's Clock app.")
        if exists { evidence("named_alarm_observed_in_simulated_clock_no_sound_or_physical_snooze_claim") }
    }
}
