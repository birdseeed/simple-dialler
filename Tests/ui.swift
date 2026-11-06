import AppKit
import QuartzCore

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
        // Pure construction avoids app launch, Keychain, network and audio discovery.
        dialler.serverField.stringValue = "sip.example.com"
        dialler.userField.stringValue = "desk-phone"
        dialler.inputDevices.addItem(withTitle: "System default")
        dialler.outputDevices.addItem(withTitle: "System default")
        let sheet = dialler.buildSettingsWindow()
        dialler.settingsWindow = sheet
        sheet.contentView!.layoutSubtreeIfNeeded()
        let stack = sheet.contentView!.subviews.compactMap { $0 as? NSStackView }.first!
        for control in stack.arrangedSubviews {
            let bounds = control.convert(control.bounds, to: sheet.contentView!)
            assert(bounds.minY >= 0 && bounds.maxY <= sheet.contentView!.bounds.height,
                   "Settings control outside visible content: \(control)")
        }
        let buttons = stack.arrangedSubviews.last as! NSStackView
        assert(buttons.arrangedSubviews.compactMap { $0 as? NSButton }.map(\.title) == ["Cancel", "Save & connect"],
               "Settings save/cancel controls must be present and ordered")
        assert(dialler.serverField.nextKeyView === dialler.userField)
        assert(dialler.userField.nextKeyView === dialler.passwordField)
        assert(dialler.number.accessibilityLabel() == "Phone number")
        assert(dialler.settingsButton.accessibilityLabel() == "Settings")
        assert(dialler.clearRecents.accessibilityLabel() == "Clear recents")
        dialler.window.contentView!.layoutSubtreeIfNeeded()
        assert(!dialler.window.contentView!.hasAmbiguousLayout)
        assert(!sheet.contentView!.hasAmbiguousLayout)
        if let folder = ProcessInfo.processInfo.environment["SIMPLE_DIALLER_UI_SCREENSHOTS"] {
            func render(_ view: NSView, name: String, appearance: NSAppearance.Name) {
                view.appearance = NSAppearance(named: appearance)
                // Offscreen windows make native layer-backed controls drawable without
                // activating the app or invoking its launch delegate.
                view.window?.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                view.window?.orderFront(nil)
                view.window?.makeFirstResponder(nil)
                view.layoutSubtreeIfNeeded()
                view.window?.displayIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                view.display()
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width),
                    pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = view.bounds.size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                view.effectiveAppearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    view.bounds.fill()
                    if let context = NSGraphicsContext.current?.cgContext {
                        view.layer?.render(in: context)
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
                try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
            }
            try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            dialler.registration.stringValue = "Connected"
            dialler.registration.textColor = .systemGreen
            dialler.callButton.isEnabled = true
            dialler.number.stringValue = "020 7946 0123"
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                render(dialler.window.contentView!, name: "dialler-" + suffix, appearance: appearance)
                render(sheet.contentView!, name: "settings-" + suffix, appearance: appearance)
                if suffix == "light" {
                    render(dialler.window.contentView!, name: "dialler", appearance: appearance)
                    render(sheet.contentView!, name: "account-setup", appearance: appearance)
                }
            }
        }
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
