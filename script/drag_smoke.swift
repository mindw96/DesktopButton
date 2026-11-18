// Compiled after the shared AX helpers from ui_smoke.swift by drag_smoke.sh.
import CryptoKit
import Darwin

func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func requireSandboxed(_ app: URL, readOnly: Bool = false) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["-d", "--entitlements", ":-", app.path]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    try require(process.terminationStatus == 0
                && entitlements?["com.apple.security.app-sandbox"] as? Bool == true
                && (entitlements?["com.apple.security.files.user-selected.read-only"] as? Bool == true) == readOnly
                && (entitlements?["com.apple.security.files.user-selected.read-write"] as? Bool == true) == !readOnly,
                "Unexpected sandbox or user-selected file access for \(app.lastPathComponent)")
}

func requireStoreTestApp(_ sourceURL: URL) throws {
    guard sourceURL.pathComponents.contains("Debug"), let bundleID = Bundle(url: sourceURL)?.bundleIdentifier,
          ["com.onebutton.desktop", "com.onebutton.desktop.dragtest"].contains(bundleID) else {
        throw SmokeFailure(description: "Use the Store Debug app so test-only preferences are active")
    }
    try require(Bundle(url: sourceURL)?.object(forInfoDictionaryKey: "SUFeedURL") == nil,
                "Expected the Store build without Sparkle")
    try require(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
                "Use the dragtest bundle ID while another instance is running")
    try requireSandboxed(sourceURL)
}

func launchDragApp(_ url: URL, arguments: [String]) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    let useKoreanUI = arguments.contains("--ui-testing") && !arguments.contains("-AppleLanguages")
    configuration.arguments = arguments + (useKoreanUI ? ["-AppleLanguages", "(ko)"] : [])
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    var result: NSRunningApplication?
    var failure: Error?
    var complete = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        result = app
        failure = error
        complete = true
    }
    try require(until(10) { complete }, "App launch timed out")
    if let failure { throw failure }
    guard let result else { throw SmokeFailure(description: "App launch returned no process") }
    try require(until(10) {
        NSRunningApplication(processIdentifier: result.processIdentifier)?.isFinishedLaunching == true
    }, "App did not finish launching")
    pumpRunLoop(1)
    return result
}

func stopDragApp(_ app: NSRunningApplication) {
    let pid = app.processIdentifier
    guard kill(pid, 0) == 0 else { return }
    app.terminate()
    if !until(3, { kill(pid, 0) != 0 }) { app.forceTerminate() }
}

func dragFile(_ element: AXUIElement, to end: CGPoint, sourcePID: pid_t, cancel: Bool = false) throws {
    let frame = try observedFrame(element)
    let start = CGPoint(x: frame.midX, y: frame.midY)
    try requirePointOnDisplay(start)
    try requirePointOnDisplay(end)
    var point = start
    func post(_ type: CGEventType, at point: CGPoint) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else {
            throw SmokeFailure(description: "Could not create file drag event")
        }
        event.flags = []
        event.post(tap: .cghidEventTap)
        pumpRunLoop(0.06)
    }
    try post(.mouseMoved, at: start)
    try post(.leftMouseDown, at: start)
    defer { try? post(.leftMouseUp, at: point) }
    // Cross the normal drag threshold before travelling to the other application.
    point = CGPoint(x: start.x - 12, y: start.y + 2)
    try post(.leftMouseDragged, at: point)
    pumpRunLoop(0.25)
    for step in 1...28 {
        let fraction = CGFloat(step) / 28
        point = CGPoint(x: start.x + (end.x - start.x) * fraction,
                        y: start.y + (end.y - start.y) * fraction)
        try post(.leftMouseDragged, at: point)
    }
    if cancel {
        try key(53, to: sourcePID, system: true)
        pumpRunLoop(0.3)
    }
}

func dragBlank(from start: CGPoint, to end: CGPoint, flags: CGEventFlags = [],
               whilePressed: (_ move: (CGPoint) throws -> Void) throws -> Void = { _ in }) throws {
    try requirePointOnDisplay(start)
    try requirePointOnDisplay(end)
    func post(_ type: CGEventType, _ point: CGPoint) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else {
            throw SmokeFailure(description: "Could not create rectangle selection event")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        pumpRunLoop(0.05)
    }
    try post(.mouseMoved, start)
    try post(.leftMouseDown, start)
    var last = start
    func move(_ point: CGPoint) throws {
        try requirePointOnDisplay(point)
        last = point
        try post(.leftMouseDragged, point)
    }
    defer { try? post(.leftMouseUp, last) }
    if start != end {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            try move(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
    }
    try whilePressed(move)
}

func receiveState(_ app: AXUIElement) -> [String: Any]? {
    guard let label = identified("fixture.drop.result", in: app),
          let text = value(label, kAXValueAttribute) as? String,
          let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func openTestDocumentExists(_ url: URL) -> Bool {
    guard let editor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { return false }
    let ax = AXUIElementCreateApplication(editor.processIdentifier)
    return children(ax, kAXWindowsAttribute).contains { window in
        guard let path = value(window, kAXDocumentAttribute) as? String, let candidate = URL(string: path) else { return false }
        return candidate.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
    }
}

func closeDragFixtureDocument(_ url: URL) throws {
    try require(until(6) { openTestDocumentExists(url) }, "The clicked fixture did not open in TextEdit")
    guard let editor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
        throw SmokeFailure(description: "Fixture editor disappeared before cleanup")
    }
    let ax = AXUIElementCreateApplication(editor.processIdentifier)
    func fixtureIsFocused() -> Bool {
        guard let window = elementValue(ax, kAXFocusedWindowAttribute),
              let path = value(window, kAXDocumentAttribute) as? String, let document = URL(string: path) else { return false }
        return document.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
    }
    editor.activate(options: [])
    try require(until(4) {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == editor.processIdentifier && fixtureIsFocused()
    }, "Fixture editor is not focused; leaving other documents untouched")
    // A direct-to-PID shortcut can be ignored after a drag; close only the verified active fixture tab.
    try key(13, to: editor.processIdentifier, flags: .maskCommand, system: true)
    try require(until(4) { !openTestDocumentExists(url) }, "The verified fixture tab did not close")
}

func showTestPanel(_ process: NSRunningApplication, at sourceURL: URL, in app: AXUIElement) throws {
    if identified("desktop.sort", in: app) == nil {
        try require(process.bundleURL?.resolvingSymlinksInPath() == sourceURL.resolvingSymlinksInPath(),
                    "Refusing to reopen an unexpected app")
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        reopen.arguments = ["-a", sourceURL.path]
        try reopen.run()
        reopen.waitUntilExit()
        try require(reopen.terminationStatus == 0, "Could not reopen test app")
    }
    try require(until(5) { identified("desktop.sort", in: app) != nil }, "Test popup missing")
    let displays = NSScreen.screens.compactMap { screen -> CGRect? in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDisplayBounds(number.uint32Value)
    }
    let frame = try observedWindowFrame(process.processIdentifier)
    if !displays.contains(where: { $0.contains(frame) }) {
        guard let screen = displays.first(where: { $0.width > frame.width + 40 && $0.height > frame.height + 80 }),
              let window = find(contentRoots(app), maxDepth: 4, matching: {
                  let role = value($0, kAXRoleAttribute) as? String
                  guard role == kAXWindowRole || role == "AXPopover" else { return false }
                  guard let candidate = try? observedFrame($0) else { return false }
                  return candidate.width > 200 && candidate.height > 100
              }) else { throw SmokeFailure(description: "Could not place isolated test popup on a physical screen: popup=\(frame), displays=\(displays)") }
        var origin = CGPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2)
        try require(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString,
                    AXValueCreate(.cgPoint, &origin)!) == .success, "Test popup reposition failed")
        pumpRunLoop(0.3)
        print("TEST WINDOW: moved isolated popup onto a physical display")
    }
    let observed = try observedWindowFrame(process.processIdentifier)
    try require(displays.contains(where: { $0.contains(observed) }), "Test popup remains outside physical displays")
}

func runDragChecks(root: URL, sourceURL: URL, receiverURL: URL) throws {
    try require(AXIsProcessTrusted(), "Accessibility permission is unavailable")
    try require(NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow", "The Mac is locked")
    try requireStoreTestApp(sourceURL)
    try requireSandboxed(receiverURL, readOnly: true)
    let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FolderInBar-Drag-\(UUID().uuidString)")
    let folder = testRoot.appendingPathComponent("작업 자료")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testRoot) }
    let image = folder.appendingPathComponent("01 사진 테스트.png")
    let document = folder.appendingPathComponent("02 문서 & notes.txt")
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=")!
    try png.write(to: image)
    try Data("Folder In Bar drag fixture. Original content must remain unchanged.\n".utf8).write(to: document)
    let originals = try [image, document].reduce(into: [String: Data]()) { $0[$1.lastPathComponent] = try Data(contentsOf: $1) }
    let unique = UUID().uuidString
    let trashFile = folder.appendingPathComponent("03 메모 \(unique.prefix(8)).txt")
    let trashFolder = folder.appendingPathComponent("04 보관 \(unique.prefix(8))", isDirectory: true)
    let nested = trashFolder.appendingPathComponent("inside.txt")
    let sentinel = Data(unique.utf8)
    try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: false)
    try sentinel.write(to: trashFile)
    try sentinel.write(to: nested)
    var launched: [NSRunningApplication] = []
    defer {
        if openTestDocumentExists(document) { try? closeDragFixtureDocument(document) }
        launched.reversed().forEach(stopDragApp)
    }
    let receiver = try launchDragApp(receiverURL, arguments: ["--probe", image.path])
    launched.append(receiver)
    let receiverAX = AXUIElementCreateApplication(receiver.processIdentifier)
    try require(until(5) { receiveState(receiverAX) != nil }, "Receiver status was not exposed")
    try require(receiveState(receiverAX)?["preflightDenied"] as? Bool == true,
                "Sandbox receiver could already read the source before any drop")
    print("PASS: sandbox receiver cannot read the ungranted source file before dropping")

    let source = try launchDragApp(sourceURL, arguments: ["--ui-testing", "--reset-test-state"])
    launched.append(source)
    pumpRunLoop(4)
    source.activate(options: [])
    pumpRunLoop(1)
    let sourceAX = AXUIElementCreateApplication(source.processIdentifier)
    try showTestPanel(source, at: sourceURL, in: sourceAX)
    try require(until(5) { identified("desktop.connect", in: sourceAX) != nil }, "Connect control missing")
    try press(identified("desktop.connect", in: sourceAX), "connect test folder")
    try require(until(5) { labeled("연결", in: sourceAX) != nil }, "Folder picker did not appear")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
                "Source app is not frontmost; no path typed")
    try key(5, to: source.processIdentifier, flags: [.maskCommand, .maskShift], system: true)
    pumpRunLoop(0.5)
    var field: AXUIElement?
    try require(until(4) {
        field = elementValue(sourceAX, kAXFocusedUIElementAttribute)
        return field.map { [kAXTextFieldRole, kAXComboBoxRole].contains(value($0, kAXRoleAttribute) as? String ?? "") } == true
    }, "Folder picker path field missing")
    guard let field else { throw SmokeFailure(description: "Picker path field disappeared") }
    if AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, folder.path as CFString) != .success {
        try clickObserved(field)
        try key(0, to: source.processIdentifier, flags: .maskCommand, system: true)
        pumpRunLoop(0.2)
        try typeText(folder.path)
    }
    try require(until(3) {
        guard let path = value(field, kAXValueAttribute) as? String else { return false }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath() == folder.resolvingSymlinksInPath()
    },
                "Picker path differs from the temporary test directory")
    try key(36, to: source.processIdentifier, system: true)
    try require(until(4) { labeled(folder.lastPathComponent, in: sourceAX) != nil }, "Picker did not show test directory")
    try press(labeled("연결", in: sourceAX), "confirm test directory")
    try require(until(5) { labeled("연결", in: sourceAX) == nil }, "Folder picker did not close")

    var count = 0
    var gestures = 0
    func item(_ file: URL) throws -> AXUIElement {
        guard let item = identified("desktop.item.\(file.lastPathComponent)", in: sourceAX) else {
            throw SmokeFailure(description: "Source item missing: \(file.lastPathComponent)")
        }
        return item
    }
    func verifyDrop(_ files: [URL], mode: String, expectedBytes: [String: Data]) throws {
        guard let target = identified("fixture.dropzone", in: receiverAX) else {
            throw SmokeFailure(description: "Drag receiver disappeared")
        }
        let dropFrame = try observedFrame(target)
        let popup = try observedWindowFrame(source.processIdentifier)
        let points = [CGPoint(x: dropFrame.midX, y: dropFrame.midY),
                      CGPoint(x: dropFrame.minX + 30, y: dropFrame.maxY - 30)]
        guard let targetPoint = points.first(where: { !popup.contains($0) }) else {
            throw SmokeFailure(description: "Popover covers the receiver; adjust fixture window position")
        }
        try dragFile(item(files[0]), to: targetPoint, sourcePID: source.processIdentifier)
        count += files.count
        gestures += 1
        try require(until(8) { (receiveState(receiverAX)?["drops"] as? [[String: Any]])?.count == count },
                    "\(mode) \(files.map(\.lastPathComponent)) drop failed: \(receiveState(receiverAX) ?? [:])")
        guard let state = receiveState(receiverAX), let drops = state["drops"] as? [[String: Any]],
              let masks = state["sourceMasks"] as? [UInt] else { throw SmokeFailure(description: "Missing drop evidence") }
        let batch = drops.suffix(files.count)
        try require(Set(batch.compactMap { $0["name"] as? String }) == Set(files.map(\.lastPathComponent)),
                    "Receiver did not obtain each selected file exactly once")
        for received in batch {
            guard let name = received["name"] as? String, let expected = expectedBytes[name] else {
                throw SmokeFailure(description: "Invalid filename")
            }
            try require(received["sha256"] as? String == hash(expected) && received["byteCount"] as? Int == expected.count,
                        "Receiver did not obtain the original bytes for \(name)")
        }
        try require(masks.count == gestures && masks.allSatisfy { $0 & NSDragOperation.copy.rawValue != 0 && $0 & NSDragOperation.move.rawValue == 0 },
                    "Each gesture must produce exactly one copy-only drop")
        try require(!openTestDocumentExists(document), "Dragging triggered the file's click-open action")
        print("PASS: \(mode) one cross-sandbox drop delivered \(files.count) selected file(s) with original names and bytes")
    }
    for mode in ["list", "grid"] {
        for (index, files) in [[image], [document], [image, document], [image, document]].enumerated() {
            try showTestPanel(source, at: sourceURL, in: sourceAX)
            try press(identified("desktop.view.\(mode)", in: sourceAX), "\(mode) layout")
            let first = files[0]
            try require(until(5) { (try? item(first)) != nil }, "Source item missing")
            if index == 3 {
                let a = try observedFrame(item(image)), b = try observedFrame(item(document))
                let blank = mode == "list" ? CGPoint(x: a.minX - 3, y: a.midY)
                                           : CGPoint(x: b.midX, y: b.minY - 5)
                let end = mode == "list" ? CGPoint(x: b.midX, y: b.midY)
                                         : CGPoint(x: a.midX, y: a.midY)
                let last = try observedFrame(item(trashFolder))
                let belowItems = CGPoint(x: last.midX, y: last.maxY + 8)
                try dragBlank(from: belowItems, to: belowItems)
                try require(until(2) {
                    guard let trash = identified("desktop.trash", in: sourceAX) else { return false }
                    return value(trash, kAXEnabledAttribute) as? Bool == false
                }, "\(mode) clicking empty space below the items did not clear the selection at \(belowItems)")
                try clickObserved(item(trashFile))
                try dragBlank(from: blank, to: end, flags: .maskShift) { _ in
                    try require(until(2) { labeled("3개 선택됨", in: sourceAX) != nil },
                                "\(mode) additive rectangle did not select the original plus the two hits")
                    try key(53, to: source.processIdentifier, system: true)
                }
                guard let trash = identified("desktop.trash", in: sourceAX) else {
                    throw SmokeFailure(description: "\(mode) Escape closed the popup during rectangle selection")
                }
                try press(trash, "inspect restored selection")
                try require(labeled("‘\(trashFile.lastPathComponent)’ 항목을 휴지통으로 옮길까요?", in: sourceAX) != nil,
                            "\(mode) Escape did not restore the original single-file selection")
                try press(identified("desktop.trash.cancel", in: sourceAX), "keep restored file")
                try dragBlank(from: blank, to: end) { _ in
                    try require(until(2) { labeled("2개 선택됨", in: sourceAX) != nil },
                                "\(mode) rectangle did not select the two files before mouse-up")
                    if mode == "grid" {
                        screenshot(source.processIdentifier, to: root.appendingPathComponent(".test-artifacts/marquee-grid.png"))
                    }
                }
                print("PASS: \(mode) empty-click clears, rectangle updates during dragging, Shift adds, Escape cancels")
            } else {
                try clickObserved(item(first))
                if files.count > 1 {
                    try clickObserved(item(files[1]), flags: mode == "list" ? .maskCommand : .maskShift)
                }
            }
            try verifyDrop(files, mode: mode, expectedBytes: originals)
        }
    }
    if identified("desktop.item.\(document.lastPathComponent)", in: sourceAX) == nil { try showTestPanel(source, at: sourceURL, in: sourceAX) }
    guard let cancelItem = identified("desktop.item.\(document.lastPathComponent)", in: sourceAX),
          let target = identified("fixture.dropzone", in: receiverAX) else { throw SmokeFailure(description: "Cancellation controls missing") }
    let targetFrame = try observedFrame(target)
    try dragFile(cancelItem, to: CGPoint(x: targetFrame.midX, y: targetFrame.midY), sourcePID: source.processIdentifier, cancel: true)
    pumpRunLoop(0.8)
    try require((receiveState(receiverAX)?["drops"] as? [[String: Any]])?.count == count && !openTestDocumentExists(document),
                "Canceled drag imported or opened a file")
    print("PASS: Escape cancels dragging without importing or opening the file")
    if identified("desktop.item.\(document.lastPathComponent)", in: sourceAX) == nil { try showTestPanel(source, at: sourceURL, in: sourceAX) }
    try require(until(5) { identified("desktop.item.\(document.lastPathComponent)", in: sourceAX) != nil }, "Click-open item missing")
    try clickObserved(identified("desktop.item.\(document.lastPathComponent)", in: sourceAX)!)
    pumpRunLoop(NSEvent.doubleClickInterval + 0.2)
    try require(!openTestDocumentExists(document), "Single click unexpectedly opened the fixture document")
    try doubleClickObserved(identified("desktop.item.\(document.lastPathComponent)", in: sourceAX)!)
    try require(until(6) { openTestDocumentExists(document) }, "Double-click did not open the fixture document")
    print("PASS: single click selects without opening; double-click opens the file in its default app")
    try closeDragFixtureDocument(document)
    print("PASS: only the verified temporary document tab was closed")
    for (name, bytes) in originals {
        try require(try Data(contentsOf: folder.appendingPathComponent(name)) == bytes, "Dragging changed or deleted an original")
    }
    print("PASS: original files remain present and byte-for-byte unchanged")
    try showTestPanel(source, at: sourceURL, in: sourceAX)
    try clickObserved(item(image))
    try key(0, to: source.processIdentifier, flags: .maskCommand)
    try require(until(4) { labeled("4개 선택됨", in: sourceAX) != nil }, "Command+A did not select all four fixtures")
    print("PASS: Command+A selects all four fixtures in the open popup")
    try clickObserved(item(trashFile))
    try clickObserved(item(trashFolder), flags: .maskCommand)
    try press(identified("desktop.trash", in: sourceAX), "move selected fixtures to Trash")
    try require(until(4) { identified("desktop.trash.cancel", in: sourceAX) != nil }, "Trash confirmation missing")
    try press(identified("desktop.trash.cancel", in: sourceAX), "cancel move to Trash")
    try require(until(4) { identified("desktop.trash.cancel", in: sourceAX) == nil }, "Trash confirmation did not close")
    try require(try Data(contentsOf: trashFile) == sentinel && Data(contentsOf: nested) == sentinel,
                "Cancellation changed the selected file or nested folder")
    print("PASS: canceling a multiple-item trash operation preserves both the file and the folder contents")

    let fileHandle = try FileHandle(forReadingFrom: trashFile)
    let nestedHandle = try FileHandle(forReadingFrom: nested)
    defer { try? fileHandle.close(); try? nestedHandle.close() }
    try clickObserved(item(trashFile))
    try clickObserved(item(trashFolder), flags: .maskCommand)
    try key(51, to: source.processIdentifier, flags: .maskCommand)
    try require(until(4) { identified("desktop.trash.confirm", in: sourceAX) != nil }, "Command+Delete did not ask for confirmation")
    try press(identified("desktop.trash.confirm", in: sourceAX), "confirm move of the two test fixtures to Trash")
    try require(until(8) { !FileManager.default.fileExists(atPath: trashFile.path) && !FileManager.default.fileExists(atPath: trashFolder.path) },
                "Confirmed trash did not remove both fixtures from the connected folder")
    try require(until(4) { (try? item(trashFile)) == nil && (try? item(trashFolder)) == nil && (try? item(image)) != nil },
                "List contents did not refresh after trashing the selection")
    for (handle, original) in [(fileHandle, trashFile), (nestedHandle, nested)] {
        // Follow only the two descriptors opened by this harness; never enumerate the user's Trash.
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        try require(fcntl(handle.fileDescriptor, F_GETPATH, &path) == 0, "Cannot locate the trashed test fixture")
        let relocated = URL(fileURLWithPath: String(cString: path))
        try require(relocated.pathComponents.contains(".Trash") || relocated.pathComponents.contains(".Trashes"),
                    "File disappeared without reaching a macOS Trash directory: \(relocated.path)")
        try require(relocated.lastPathComponent == original.lastPathComponent && (try handle.readToEnd()) == sentinel,
                    "The trashed fixture lost its name or original bytes")
        let movedItem = original == nested ? relocated.deletingLastPathComponent() : relocated
        let restoreTo = original == nested ? trashFolder : trashFile
        try require(movedItem.lastPathComponent == restoreTo.lastPathComponent, "Trash renamed the unique fixture")
        do {
            try FileManager.default.moveItem(at: movedItem, to: restoreTo)
        } catch {
            print("Fixture is recoverable in Trash: \(movedItem.lastPathComponent) (test runner could not move it back)")
        }
    }
    for (name, bytes) in originals {
        try require(try Data(contentsOf: folder.appendingPathComponent(name)) == bytes, "Trashing selected items changed an unselected original")
    }
    print("PASS: file and complete folder moved to macOS Trash; nested data remains readable and unselected files remain unchanged")
    // More items than one viewport proves scrolling while the pointer remains stationary.
    for number in 1...50 {
        try Data().write(to: folder.appendingPathComponent(String(format: "scroll-%02d.txt", number)))
    }
    let totalLabel = "\(try FileManager.default.contentsOfDirectory(atPath: folder.path).count)개 항목"
    try press(identified("desktop.view.list", in: sourceAX), "list layout for scrolling")
    try press(identified("desktop.refresh", in: sourceAX), "load scrolling fixtures")
    try require(until(5) { labeled(totalLabel, in: sourceAX) != nil },
                "Scrolling fixtures did not finish loading")
    guard let scroll = find(contentRoots(sourceAX), matching: { value($0, kAXRoleAttribute) as? String == kAXScrollAreaRole }) else {
        throw SmokeFailure(description: "File list viewport unavailable")
    }
    let viewport = try observedFrame(scroll)
    let first = try observedFrame(item(image))
    let visibleRows = Int(ceil(viewport.height / first.height)) + 1
    try dragBlank(from: CGPoint(x: first.minX - 3, y: first.midY),
                  to: CGPoint(x: first.midX, y: viewport.maxY - 3)) { move in
        try require(until(8) {
            find(contentRoots(sourceAX), matching: { element in
                let text = (value(element, kAXValueAttribute) as? String) ?? ""
                guard text.hasSuffix("개 선택됨"), let count = Int(text.prefix(while: { $0.isNumber })) else { return false }
                return count > visibleRows + 3
            }) != nil
        }, "Holding at the bottom edge did not select items past the original \(visibleRows) visible rows")
        try move(CGPoint(x: first.midX, y: viewport.minY + 3))
        try require(until(8) {
            guard let restored = try? observedFrame(item(image)) else { return false }
            return abs(restored.midY - first.midY) <= 2 && labeled(totalLabel, in: sourceAX) != nil
        }, "Holding at the top edge did not return to the starting row and shrink the selection")
    }
    print("PASS: stationary bottom-edge drag selects offscreen rows; returning to the top edge scrolls back and shrinks the selection")
    let extra = [folder.appendingPathComponent("scroll-01.txt"), folder.appendingPathComponent("scroll-02.txt")]
    let four = [image, document] + extra
    try clickObserved(item(image))
    for file in four.dropFirst() { try clickObserved(item(file), flags: .maskCommand) }
    try require(until(4) { labeled("4개 선택됨", in: sourceAX) != nil }, "Could not select four files")
    var expectedBytes = originals
    for file in extra { expectedBytes[file.lastPathComponent] = try Data(contentsOf: file) }
    try verifyDrop(four, mode: "list", expectedBytes: expectedBytes)
    try showTestPanel(source, at: sourceURL, in: sourceAX)
    try clickObserved(item(image))
    try require(until(3) {
        guard let trash = identified("desktop.trash", in: sourceAX) else { return false }
        return value(trash, kAXEnabledAttribute) as? Bool == true
    }, "The original file must be selected before replacement")
    try png.write(to: image, options: .atomic)
    try press(identified("desktop.refresh", in: sourceAX), "refresh after same-name file replacement")
    try require(until(5) {
        guard let trash = identified("desktop.trash", in: sourceAX) else { return false }
        return (try? item(image)) != nil && value(trash, kAXEnabledAttribute) as? Bool == false
    }, "Selection transferred to a different file at the same path")

    let renamed = testRoot.appendingPathComponent("Renamed", isDirectory: true)
    try FileManager.default.moveItem(at: folder, to: renamed)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let decoy = folder.appendingPathComponent("replacement-only.txt")
    try sentinel.write(to: decoy)
    try press(identified("desktop.refresh", in: sourceAX), "refresh after folder path reuse")
    try require(until(5) {
        labeled(renamed.lastPathComponent, in: sourceAX) != nil || identified("desktop.error", in: sourceAX) != nil
    }, "The app neither followed the original folder nor requested reconnection")
    try require((try? item(decoy)) == nil, "The replacement folder was displayed")
    print("PASS: refreshing clears same-name replacement selection and never lists the replacement folder")
    let artifacts = root.appendingPathComponent(".test-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    if var state = receiveState(receiverAX) {
        state["replacementFileDeselected"] = true
        state["replacementFolderExcluded"] = true
        state["trash"] = ["cancelPreservedSelection": true, "fileAndFolderReachedTrash": true, "unselectedOriginalsPreserved": true]
        state["marquee"] = ["listAndGridTwoFileDrops": true, "liveSelection": true, "escapeRestoresSelection": true,
                             "plainClickClears": true, "stationaryEdgeScroll": true]
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: artifacts.appendingPathComponent("drag-smoke-result.json"))
    }
    screenshot(receiver.processIdentifier, to: artifacts.appendingPathComponent("drag-receiver.png"))
}

setbuf(stdout, nil)
do {
    try require(CommandLine.arguments.count == 4, "usage: script/drag_smoke.sh PROJECT_ROOT STORE_DEBUG_APP RECEIVER_APP")
    try runDragChecks(root: URL(fileURLWithPath: CommandLine.arguments[1]),
                      sourceURL: URL(fileURLWithPath: CommandLine.arguments[2]),
                      receiverURL: URL(fileURLWithPath: CommandLine.arguments[3]))
    print("Native file drag checks completed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
