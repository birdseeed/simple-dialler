import AppKit
import AVFoundation
import Security
import Network

final class Dialler: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    let statusMenu = NSMenu()
    let menuStatus = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
    var menuSettings: NSMenuItem?
    let number = NSTextField(string: "")
    let registration = NSTextField(labelWithString: "Not connected")
    let callStatus = NSTextField(labelWithString: "Ready to dial")
    let remote = NSTextField(labelWithString: " ")
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let callButton = NSButton(title: "Call", target: nil, action: nil)
    let hangupButton = NSButton(title: "Hang up", target: nil, action: nil)
    let muteButton = NSButton(checkboxWithTitle: "Mute microphone", target: nil, action: nil)
    let settingsButton = NSButton(title: "Settings…", target: nil, action: nil)
    var timer: Timer?
    var ringTimer: Timer?
    var eventMonitor: Any?
    var wakeObserver: NSObjectProtocol?
    var attention: Int?
    var lastCall: Int32 = 0
    var lastGeneration: UInt32 = 0
    var awaitingMicrophone = false
    var settings = AccountSettings.load()
    lazy var history = CallHistory(account: settings.keychainAccount)
    let recents = NSPopUpButton(frame: .zero, pullsDown: false)
    let clearRecents = NSButton(title: "Clear recents", target: nil, action: nil)
    let seenButton = NSButton(title: "Mark seen", target: nil, action: nil)
    let reconnectButton = NSButton(title: "Reconnect", target: nil, action: nil)
    let inputDevices = NSPopUpButton(frame: .zero, pullsDown: false)
    let outputDevices = NSPopUpButton(frame: .zero, pullsDown: false)
    let audioCheck = NSButton(checkboxWithTitle: "Check microphone locally", target: nil, action: nil)
    let audioLevel = NSLevelIndicator()
    let audioNote = NSTextField(wrappingLabelWithString: "")
    var selectedInput = UserDefaults.standard.string(forKey: "audioInputName")
    var selectedOutput = UserDefaults.standard.string(forKey: "audioOutputName")
    var lastDeviceScan: TimeInterval = 0
    var recovery = RecoveryPolicy()
    let pathMonitor = NWPathMonitor()
    var networkOnline = true
    var lastPath: NWPath?
    var settingsWindow: NSWindow?
    let serverField = NSTextField(string: "")
    let userField = NSTextField(string: "")
    let passwordField = NSSecureTextField(string: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        buildMenu()
        buildWindow()
        buildStatusItem()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refreshUI() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.recovery.request(now: ProcessInfo.processInfo.systemUptime)
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.networkOnline = path.status == .satisfied
                if self.lastPath != nil { self.recovery.request(now: ProcessInfo.processInfo.systemUptime) }
                self.lastPath = path
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "simple-dialler.network"))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(number)
        if DialRules.validServer(settings.server), DialRules.validUsername(settings.username) {
            let (password, status) = PasswordStore.read(settings.keychainAccount)
            if let password { connect(password); return }
            if status != errSecItemNotFound {
                errorLabel.stringValue = "Keychain access failed (\(status)). Open Settings to reconnect."
            }
        }
        showSettings(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDialler(nil)
        return false
    }

    @objc func showDialler(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        // Preserve the Settings sheet's current field, including password entry.
        if window.attachedSheet == nil && number.isEnabled { window.makeFirstResponder(number) }
    }

    func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "phone", accessibilityDescription: "Simple Dialler")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Simple Dialler — click to open, right-click for menu"
            button.setAccessibilityLabel("Simple Dialler")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu.autoenablesItems = false
        let open = statusMenu.addItem(withTitle: "Open Simple Dialler", action: #selector(showDialler(_:)), keyEquivalent: "")
        open.target = self
        menuStatus.isEnabled = false
        statusMenu.addItem(menuStatus)
        statusMenu.addItem(.separator())
        let preferences = statusMenu.addItem(withTitle: "Settings…", action: #selector(statusSettings(_:)), keyEquivalent: "")
        preferences.target = self
        menuSettings = preferences
        statusMenu.addItem(.separator())
        let quit = statusMenu.addItem(withTitle: "Quit Simple Dialler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
    }

    @objc func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem?.button {
            refreshUI()
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else {
            showDialler(nil)
        }
    }

    @objc func statusSettings(_ sender: Any?) {
        showDialler(nil)
        showSettings(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if sd_state().call != 0 {
            let alert = NSAlert()
            alert.messageText = "End the call and quit?"
            alert.addButton(withTitle: "End call and quit")
            alert.addButton(withTitle: "Keep calling")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        pathMonitor.cancel()
        timer?.invalidate()
        stopRinging()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        sd_stop()
    }

    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Simple Dialler", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let preferences = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Simple Dialler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Simple Dialler"
        window.center()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24)
        ])
        registration.maximumNumberOfLines = 3
        registration.alignment = .center
        registration.font = .systemFont(ofSize: 12)
        registration.textColor = .secondaryLabelColor
        stack.addArrangedSubview(registration)
        registration.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        number.placeholderString = "Number or +44…"
        number.font = .monospacedDigitSystemFont(ofSize: 27, weight: .regular)
        number.alignment = .center
        number.bezelStyle = .roundedBezel
        number.setAccessibilityLabel("Phone number")
        stack.addArrangedSubview(number)
        number.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        number.heightAnchor.constraint(equalToConstant: 46).isActive = true
        callStatus.font = .systemFont(ofSize: 17, weight: .medium)
        recents.target = self
        recents.action = #selector(selectRecent(_:))
        recents.setAccessibilityLabel("Recent calls; choose a number then press Enter to call")
        stack.addArrangedSubview(recents)
        recents.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        clearRecents.target = self; clearRecents.action = #selector(clearHistory(_:))
        seenButton.target = self; seenButton.action = #selector(markHistorySeen(_:))
        let historyActions = NSStackView(views: [clearRecents, seenButton])
        historyActions.spacing = 12
        stack.addArrangedSubview(historyActions)
        rebuildRecents()
        stack.addArrangedSubview(callStatus)
        remote.font = .systemFont(ofSize: 12)
        remote.lineBreakMode = .byTruncatingMiddle
        remote.alignment = .center
        stack.addArrangedSubview(remote)
        remote.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let actions = NSStackView(views: [callButton, hangupButton])
        actions.spacing = 12
        callButton.target = self
        callButton.action = #selector(callOrAnswer(_:))
        callButton.bezelStyle = .rounded
        callButton.contentTintColor = .systemGreen
        hangupButton.target = self
        hangupButton.action = #selector(hangup(_:))
        hangupButton.bezelStyle = .rounded
        hangupButton.contentTintColor = .systemRed
        for button in [callButton, hangupButton] { button.widthAnchor.constraint(equalToConstant: 145).isActive = true }
        stack.addArrangedSubview(actions)
        let keypad = NSStackView()
        keypad.orientation = .vertical
        keypad.spacing = 5
        for row in ["123", "456", "789", "*0#"] {
            let buttons = row.map { character -> NSButton in
                let button = NSButton(title: String(character), target: self, action: #selector(keypadPressed(_:)))
                button.bezelStyle = .rounded
                button.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
                button.widthAnchor.constraint(equalToConstant: 92).isActive = true
                button.heightAnchor.constraint(equalToConstant: 36).isActive = true
                return button
            }
            let rowStack = NSStackView(views: buttons)
            rowStack.spacing = 7
            keypad.addArrangedSubview(rowStack)
        }
        stack.addArrangedSubview(keypad)
        muteButton.target = self
        muteButton.action = #selector(toggleMute(_:))
        stack.addArrangedSubview(muteButton)
        let hint = NSTextField(labelWithString: "Enter: call / answer   ·   Esc: hang up\nDuring a call, type 0–9, * or # for menus.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        stack.addArrangedSubview(hint)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        stack.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        errorLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        settingsButton.target = self
        settingsButton.action = #selector(showSettings(_:))
        settingsButton.bezelStyle = .rounded
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnect(_:))
        let connectionActions = NSStackView(views: [settingsButton, reconnectButton])
        connectionActions.spacing = 12
        stack.addArrangedSubview(connectionActions)
        refreshUI()
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard window.isKeyWindow, window.attachedSheet == nil,
              !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option) else { return event }
        if event.keyCode == 36 || event.keyCode == 76 {
            if !event.isARepeat { callOrAnswer(nil) }
            return nil
        }
        if event.keyCode == 53 {
            if !event.isARepeat { hangup(nil) }
            return nil
        }
        if sd_state().call == 3, let text = event.characters, text.count == 1,
           let scalar = text.unicodeScalars.first, "0123456789*#".unicodeScalars.contains(scalar) {
            if !event.isARepeat { sendDigit(text) }
            return nil // Consume it so the field/button cannot send a second tone.
        }
        return event
    }

    @objc func callOrAnswer(_ sender: Any?) {
        guard window.attachedSheet == nil, !awaitingMicrophone else { return }
        let state = sd_state()
        guard state.call == 0 || state.call == 1 else { return }
        var destination: String?
        if state.call == 0 {
            guard state.registration == 2 else { errorLabel.stringValue = "Connect your SIP account in Settings first."; return }
            guard let parsed = DialRules.normalise(number.stringValue) else {
                errorLabel.stringValue = "Enter a phone number using digits, +, * or #."; return
            }
            destination = parsed
        }
        errorLabel.stringValue = ""
        withMicrophone { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.errorLabel.stringValue = "Allow microphone access in System Settings → Privacy & Security."
                return
            }
            let now = sd_state()
            guard now.call == state.call, now.call_generation == state.call_generation else { return }
            self.stopAudioCheck()
            let result: Int32
            if let destination {
                self.number.stringValue = destination
                result = destination.withCString { sd_call($0) }
                if result == 0 {
                    self.history.record(destination, outcome: "outgoing")
                    self.rebuildRecents()
                }
            } else { result = sd_answer() }
            self.check(result, action: destination == nil ? "Answer" : "Call")
            self.refreshUI()
        }
    }

    func withMicrophone(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            awaitingMicrophone = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.awaitingMicrophone = false
                    completion(granted)
                }
            }
        default: completion(false)
        }
    }

    @objc func hangup(_ sender: Any?) {
        guard sd_state().call != 0 else { return }
        check(sd_hangup(), action: "Hang up")
        refreshUI()
    }

    @objc func toggleMute(_ sender: Any?) {
        check(sd_mute(muteButton.state == .on ? 1 : 0), action: "Mute")
        refreshUI()
    }

    @objc func keypadPressed(_ sender: NSButton) {
        let state = sd_state()
        if state.call == 3 { sendDigit(sender.title) }
        else if state.call == 0 {
            number.stringValue += sender.title
            window.makeFirstResponder(number)
            if let editor = number.currentEditor() {
                editor.selectedRange = NSRange(location: number.stringValue.utf16.count, length: 0)
            }
        }
    }

    func sendDigit(_ text: String) {
        guard let byte = text.utf8.first else { return }
        check(sd_dtmf(Int8(bitPattern: byte)), action: "Keypad tone")
    }

    func check(_ status: Int32, action: String) {
        errorLabel.stringValue = status == 0 ? "" : "\(action): \(CallPresentation.failure(status)) (Code \(status))"
    }

    func refreshUI() {
        var state = sd_state()
        let now = ProcessInfo.processInfo.systemUptime
        if recovery.shouldRefresh(now: now, online: networkOnline, idle: state.call == 0 && !awaitingMicrophone && state.running != 0) {
            check(sd_refresh(), action: "Reconnect")
        }
        var incoming = SDIncomingResult()
        var historyChanged = false
        while sd_next_incoming(&incoming) != 0 {
            let value = withUnsafePointer(to: &incoming.remote) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            history.record(value, outcome: incoming.outcome == 1 ? "missed" : (incoming.outcome == 2 ? "rejected" : "answered"))
            historyChanged = true
        }
        if historyChanged { rebuildRecents() }
        if state.call != 0 { stopAudioCheck() }
        if now - lastDeviceScan >= 3 && state.call == 0 && audioCheck.state == .off && state.running != 0 { reloadAudioDevices() }
        if audioCheck.state == .on { audioLevel.doubleValue = Double(sd_audio_level()) }
        switch state.registration {
        case 1: registration.stringValue = "Connecting…"
        case 2: registration.stringValue = "Connected"
        case 3: registration.stringValue = "\(CallPresentation.failure(state.registration_code)) (SIP \(state.registration_code))"
        default: registration.stringValue = "Not connected · open Settings"
        }
        menuStatus.title = registration.stringValue
        menuSettings?.isEnabled = state.call == 0
        registration.textColor = state.registration == 2 ? .systemGreen : .secondaryLabelColor
        switch state.call {
        case 1: callStatus.stringValue = "Incoming call"
        case 2: callStatus.stringValue = state.call_code == 180 ? "Ringing…" : "Connecting call…"
        case 3: callStatus.stringValue = "\(CallPresentation.duration(state.connected_seconds)) · \(state.muted != 0 ? "Muted" : "In call")"
        default:
            if lastCall != 0 {
                callStatus.stringValue = "Call ended"
                if state.call_code >= 300 && state.call_code != 487 {
                    errorLabel.stringValue = "\(CallPresentation.failure(state.call_code)) (SIP \(state.call_code))"
                }
            }
        }
        remote.stringValue = state.call == 0 ? " " : withUnsafePointer(to: &state.remote) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        number.isEnabled = state.call == 0
        callButton.title = state.call == 1 ? "Answer" : "Call"
        callButton.isEnabled = state.call == 1 || (state.call == 0 && state.registration == 2)
        hangupButton.title = state.call == 1 ? "Reject" : "Hang up"
        hangupButton.isEnabled = state.call != 0
        muteButton.isEnabled = state.call == 3
        muteButton.state = state.muted != 0 ? .on : .off
        settingsButton.isEnabled = state.call == 0 && !awaitingMicrophone
        reconnectButton.isEnabled = state.call == 0 && !awaitingMicrophone
        recents.isEnabled = state.call == 0
        clearRecents.isEnabled = state.call == 0 && !history.entries.isEmpty
        seenButton.isEnabled = history.missedCount > 0
        statusItem?.button?.title = history.missedCount == 0 ? "" : " \(history.missedCount)"
        statusItem?.length = history.missedCount == 0 ? NSStatusItem.squareLength : NSStatusItem.variableLength
        if state.call == 1 && (lastCall != 1 || lastGeneration != state.call_generation) {
            startRinging()
            window.orderFrontRegardless()
            attention = NSApp.requestUserAttention(.criticalRequest)
        } else if state.call != 1 { stopRinging() }
        if state.call == 0 && lastCall != 0 && window.attachedSheet == nil {
            window.makeFirstResponder(number)
            number.selectText(nil)
        }
        lastCall = state.call
        lastGeneration = state.call_generation
    }

    func startRinging() {
        stopRinging()
        ring()
        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.ring() }
    }

    func ring() {
        if let sound = NSSound(named: "Glass") { sound.play() }
        else { NSSound.beep() }
    }

    func stopRinging() {
        ringTimer?.invalidate()
        ringTimer = nil
        NSSound(named: "Glass")?.stop()
        if let attention { NSApp.cancelUserAttentionRequest(attention); self.attention = nil }
    }

    @objc func showSettings(_ sender: Any?) {
        guard sd_state().call == 0, window.attachedSheet == nil else { return }
        serverField.stringValue = settings.server
        userField.stringValue = settings.username
        passwordField.stringValue = ""
        passwordField.placeholderString = "Enter SIP password (blank keeps saved password)"
        passwordField.setAccessibilityLabel("SIP password")
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "SIP account"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sheet.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sheet.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: sheet.contentView!.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sheet.contentView!.bottomAnchor, constant: -16)
        ])
        for (title, field) in [("SIP server (UDP)", serverField), ("SIP username", userField), ("SIP password", passwordField)] {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            field.setAccessibilityLabel(title)
        }
        let note = NSTextField(wrappingLabelWithString: "Server and username can be imported from Zoiper. Enter your SIP password once; it is saved in macOS Keychain.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for (label, popup) in [("Microphone", inputDevices), ("Call output", outputDevices)] {
            stack.addArrangedSubview(NSTextField(labelWithString: label))
            popup.target = self; popup.action = #selector(selectAudio(_:))
            popup.setAccessibilityLabel(label)
            stack.addArrangedSubview(popup)
            popup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        audioCheck.target = self; audioCheck.action = #selector(checkMicrophone(_:))
        stack.addArrangedSubview(audioCheck)
        audioLevel.minValue = 0; audioLevel.maxValue = 255
        audioLevel.levelIndicatorStyle = .continuousCapacity
        audioLevel.setAccessibilityLabel("Microphone input level")
        stack.addArrangedSubview(audioLevel)
        audioLevel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        audioNote.font = .systemFont(ofSize: 11)
        audioNote.textColor = .secondaryLabelColor
        audioNote.stringValue = "Speak to check the level locally. No recording or remote audio is sent. Ringtone uses the macOS sound output. Audio choices apply now and are saved. Missing devices use the system default until they return."
        stack.addArrangedSubview(audioNote)
        audioNote.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        _ = sd_start()
        reloadAudioDevices()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings(_:)))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "Save & connect", target: self, action: #selector(saveSettings(_:)))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let actions = NSStackView(views: [cancel, save])
        actions.spacing = 12
        stack.addArrangedSubview(actions)
        settingsWindow = sheet
        window.beginSheet(sheet)
        sheet.makeFirstResponder(settings.username.isEmpty ? userField : passwordField)
    }

    @objc func cancelSettings(_ sender: Any?) {
        guard let sheet = settingsWindow else { return }
        stopAudioCheck()
        passwordField.stringValue = ""
        window.endSheet(sheet)
        settingsWindow = nil
        window.makeFirstResponder(number)
    }

    @objc func saveSettings(_ sender: Any?) {
        guard let sheet = settingsWindow, sd_state().call == 0 else { return }
        let proposed = AccountSettings(server: serverField.stringValue.trimmingCharacters(in: .whitespaces).lowercased(),
                                       username: userField.stringValue.trimmingCharacters(in: .whitespaces))
        guard DialRules.validServer(proposed.server), DialRules.validUsername(proposed.username) else {
            showSettingsError("Enter a server hostname (optionally :port) and a valid SIP username.", sheet: sheet); return
        }
        var password = passwordField.stringValue
        if password.isEmpty {
            let (saved, status) = PasswordStore.read(proposed.keychainAccount)
            guard let saved else {
                showSettingsError(status == errSecItemNotFound ? "Enter your SIP password." : "Could not read Keychain (\(status)). Enter your password again.", sheet: sheet)
                return
            }
            password = saved
        }
        guard DialRules.validPassword(password) else {
            showSettingsError("Enter a password without line breaks (up to 512 bytes).", sheet: sheet); return
        }
        let result = PasswordStore.save(password, account: proposed.keychainAccount)
        guard result == errSecSuccess else {
            showSettingsError("Could not save the password to Keychain (\(result)).", sheet: sheet); return
        }
        cancelSettings(nil)
        if connect(password, account: proposed) { settings.save() }
    }

    func showSettingsError(_ message: String, sheet: NSWindow) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: sheet)
    }

    func rebuildRecents() {
        recents.removeAllItems()
        recents.addItem(withTitle: history.missedCount > 0 ? "Recents · \(history.missedCount) missed" : "Recent calls")
        let formatter = DateFormatter()
        formatter.dateStyle = .short; formatter.timeStyle = .short
        for (index, entry) in history.entries.enumerated() {
            recents.addItem(withTitle: "\(entry.outcome.capitalized) · \(entry.number) · \(formatter.string(from: entry.date))")
            recents.lastItem?.tag = index
        }
        recents.selectItem(at: 0)
    }

    @objc func selectRecent(_ sender: Any?) {
        let index = recents.indexOfSelectedItem - 1
        guard sd_state().call == 0, history.entries.indices.contains(index) else { return }
        if let callback = CallPresentation.callbackNumber(history.entries[index].number) {
            number.stringValue = callback
            errorLabel.stringValue = ""
            window.makeFirstResponder(number)
            number.selectText(nil)
        } else { errorLabel.stringValue = "This caller did not supply a diallable telephone number." }
    }

    @objc func clearHistory(_ sender: Any?) { history.clear(); rebuildRecents() }
    @objc func markHistorySeen(_ sender: Any?) { history.markSeen(); rebuildRecents() }

    @objc func reconnect(_ sender: Any?) {
        guard sd_state().call == 0, !awaitingMicrophone else { return }
        stopAudioCheck()
        let (password, status) = PasswordStore.read(settings.keychainAccount)
        guard let password else {
            errorLabel.stringValue = "Could not read the saved password (Keychain \(status)). Open Settings."
            return
        }
        connect(password)
    }

    func reloadAudioDevices() {
        lastDeviceScan = ProcessInfo.processInfo.systemUptime
        var devices = [SDAudioDevice](repeating: SDAudioDevice(), count: 64)
        let count = sd_audio_devices(&devices, Int32(devices.count))
        inputDevices.removeAllItems(); outputDevices.removeAllItems()
        inputDevices.addItem(withTitle: "System default"); inputDevices.lastItem?.tag = -1
        outputDevices.addItem(withTitle: "System default"); outputDevices.lastItem?.tag = -2
        for var device in devices.prefix(Int(count)) {
            let name = withUnsafePointer(to: &device.name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            if device.inputs > 0 { inputDevices.addItem(withTitle: name); inputDevices.lastItem?.tag = Int(device.id) }
            if device.outputs > 0 { outputDevices.addItem(withTitle: name); outputDevices.lastItem?.tag = Int(device.id) }
        }
        if let name = selectedInput, inputDevices.itemTitles.contains(name) { inputDevices.selectItem(withTitle: name) }

        if let name = selectedOutput, outputDevices.itemTitles.contains(name) { outputDevices.selectItem(withTitle: name) }

        // Device IDs may change on hotplug. Missing choices fall back to defaults.
        _ = sd_audio_select(Int32(inputDevices.selectedTag()), Int32(outputDevices.selectedTag()))
    }

    @objc func selectAudio(_ sender: Any?) {
        stopAudioCheck()
        selectedInput = inputDevices.indexOfSelectedItem == 0 ? nil : inputDevices.titleOfSelectedItem
        selectedOutput = outputDevices.indexOfSelectedItem == 0 ? nil : outputDevices.titleOfSelectedItem
        UserDefaults.standard.set(selectedInput, forKey: "audioInputName")
        UserDefaults.standard.set(selectedOutput, forKey: "audioOutputName")
        check(sd_audio_select(Int32(inputDevices.selectedTag()), Int32(outputDevices.selectedTag())), action: "Audio selection")
    }

    @objc func checkMicrophone(_ sender: Any?) {
        guard audioCheck.state == .on else { stopAudioCheck(); return }
        withMicrophone { [weak self] allowed in
            guard let self else { return }
            guard allowed, self.settingsWindow != nil, sd_state().call == 0, self.audioCheck.state == .on else {
                self.stopAudioCheck(); return
            }
            let result = sd_audio_check(1)
            if result != 0 { self.stopAudioCheck(); self.audioNote.stringValue = "Could not open audio devices (Code \(result)). Choose another device." }
        }
    }

    func stopAudioCheck(stopCapture: () -> Void = { _ = sd_audio_check(0) }) {
        // The checkbox is already off when its action arrives. Cleanup must
        // always reach the bridge, which owns the actual capture lifetime.
        stopCapture()
        audioCheck.state = .off
        audioLevel.doubleValue = 0
    }

    @discardableResult
    func connect(_ password: String, account proposed: AccountSettings? = nil) -> Bool {
        let target = proposed ?? settings
        let admission = sd_prepare_connect()
        guard admission == 0 else {
            check(admission, action: "Connection")
            return false
        }
        // Worker callbacks can no longer admit an old-account call. Drain its
        // preserved completion queue before publishing the replacement account.
        refreshUI()
        let result = target.server.withCString { server in
            target.username.withCString { username in
                password.withCString { sd_connect(server, username, $0) }
            }
        }
        settings = target
        history = CallHistory(account: settings.keychainAccount)
        rebuildRecents()
        reloadAudioDevices()
        check(result, action: "Connection")
        refreshUI()
        window.makeFirstResponder(number)
        return true
    }

}

#if !DIALLER_UI_TEST
@main
struct DiallerApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = Dialler()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}
#endif
