import AppKit

@main
struct UITests {
    static func main() {
        _ = NSApplication.shared
        let dialler = Dialler()
        // Construct UI only: never invoke app launch, Keychain or connect.
        dialler.settings = AccountSettings(server: "example.test", username: "offline-fixture")
        dialler.history = CallHistory(account: "offline-ui-fixture", defaults: UserDefaults(suiteName: "simple-dialler-ui-tests")!)
        dialler.buildWindow()
        var stops = 0
        dialler.audioCheck.state = .off // Native checkbox action sees this state.
        dialler.stopAudioCheck { stops += 1 }
        assert(stops == 1, "Unchecking must stop the bridge even after the checkbox turns off")
        dialler.stopAudioCheck { stops += 1 }
        assert(stops == 2, "Repeated cleanup must still reach the idempotent bridge")
        dialler.showSettings(nil)
        guard let sheet = dialler.settingsWindow else { fatalError("No settings sheet") }
        sheet.contentView!.layoutSubtreeIfNeeded()
        let stack = sheet.contentView!.subviews.compactMap { $0 as? NSStackView }.first!
        for control in stack.arrangedSubviews {
            let bounds = control.convert(control.bounds, to: sheet.contentView!)
            assert(bounds.minY >= 0 && bounds.maxY <= sheet.contentView!.bounds.height,
                   "Settings control outside visible content: \(control)")
        }
        let buttons = stack.arrangedSubviews.last as! NSStackView
        assert(buttons.arrangedSubviews.count == 2, "Settings save/cancel controls must be present")
        dialler.cancelSettings(nil)
        let defaults = UserDefaults.standard
        let oldInput = defaults.object(forKey: "audioInputName")
        let oldOutput = defaults.object(forKey: "audioOutputName")
        defer {
            defaults.set(oldInput, forKey: "audioInputName")
            defaults.set(oldOutput, forKey: "audioOutputName")
        }
        dialler.inputDevices.addItem(withTitle: "Offline fixture microphone")
        dialler.inputDevices.lastItem?.tag = -1
        dialler.inputDevices.selectItem(withTitle: "Offline fixture microphone")
        dialler.selectAudio(nil) // No-immediate-open device configuration only.
        let relaunched = Dialler()
        assert(relaunched.selectedInput == "Offline fixture microphone", "Device choice must survive a new app instance")
        sd_stop()
        assert(sd_start() == 0)
        relaunched.reloadAudioDevices()
        assert(relaunched.inputDevices.selectedTag() == -1, "Unavailable saved input must use system default")
        assert(relaunched.selectedInput == "Offline fixture microphone", "Fallback must retain saved preference for reconnect")
        sd_stop()
        print("Passed offline AppKit checkbox cleanup, saved-device fallback and settings geometry checks. No credentials, provider or audio opened.")
    }
}
