import AppKit
import ApplicationServices

// Run with: swift script/ui_smoke.swift /absolute/path/to/OneButton
// Uses its own temporary folder and the app's DEBUG-only test preferences.
struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw SmokeFailure(description: message) }
}

func pumpRunLoop(_ seconds: TimeInterval = 0.1) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@discardableResult
func until(_ seconds: TimeInterval, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if predicate() { return true }
        pumpRunLoop()
    } while Date() < deadline
    return false
}

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(element, 0.3)
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
    return result
}

func elementValue(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    return (result as! AXUIElement)
}

func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
    value(element, attribute) as? [AXUIElement] ?? []
}

// Bound each search to 160 nodes / 2 seconds; only inspect our app content or the named overflow control.
func find(_ roots: [AXUIElement], maxDepth: Int = 8, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(2)
    var queue = roots.prefix(8).map { ($0, 0) }
    var offset = 0
    var visited = 0
    while offset < queue.count, visited < 160, Date() < deadline {
        let (element, depth) = queue[offset]
        offset += 1
        visited += 1
        if predicate(element) { return element }
        if depth < maxDepth {
            queue.append(contentsOf: children(element).prefix(80).map { ($0, depth + 1) })
        }
    }
    return nil
}

func contentRoots(_ app: AXUIElement) -> [AXUIElement] {
    var roots = children(app, kAXWindowsAttribute)
        + [elementValue(app, kAXFocusedWindowAttribute), elementValue(app, kAXMainWindowAttribute)].compactMap { $0 }
        + children(app).filter { value($0, kAXRoleAttribute) as? String != kAXMenuBarRole }
    if let item = menuItem(app) { roots += children(item) }
    if let popover = find(roots, maxDepth: 4, matching: { value($0, kAXRoleAttribute) as? String == "AXPopover" }) {
        roots.insert(popover, at: 0)
    }
    return roots
}

func identified(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
    find(contentRoots(app)) { value($0, kAXIdentifierAttribute) as? String == identifier }
}

func labeled(_ label: String, in app: AXUIElement) -> AXUIElement? {
    find(contentRoots(app)) {
        (value($0, kAXTitleAttribute) as? String == label)
            || (value($0, kAXValueAttribute) as? String == label)
            || (value($0, kAXDescriptionAttribute) as? String == label)
    }
}


func press(_ element: AXUIElement?, _ description: String) throws {
    guard let element else { throw SmokeFailure(description: "Missing control: \(description)") }
    try require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success,
                "AXPress failed: \(description)")
}

func key(_ code: CGKeyCode, to pid: pid_t, flags: CGEventFlags = [], system: Bool = false) throws {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
            throw SmokeFailure(description: "Could not create keyboard event")
        }
        event.flags = flags
        if system { event.post(tap: .cghidEventTap) } else { event.postToPid(pid) }
    }
}

func typeText(_ text: String) throws {
    let units = Array(text.utf16)
    for start in stride(from: 0, to: units.count, by: 16) {
        let chunk = Array(units[start..<min(start + 16, units.count)])
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
                throw SmokeFailure(description: "Could not create text event")
            }
            event.flags = []
            chunk.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!)
            }
            event.post(tap: .cghidEventTap)
        }
        pumpRunLoop(0.03)
    }
}

func menuItem(_ app: AXUIElement) -> AXUIElement? {
    guard let extras = elementValue(app, kAXExtrasMenuBarAttribute) else { return nil }
    return children(extras).first
}

func observedFrame(_ element: AXUIElement) throws -> CGRect {
    guard let positionValue = value(element, kAXPositionAttribute),
          let sizeValue = value(element, kAXSizeAttribute),
          CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        throw SmokeFailure(description: "Control has no observed frame")
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    try require(AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                && AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), "Could not read control frame")
    return CGRect(origin: position, size: size)
}

func clickObserved(_ element: AXUIElement) throws {
    let frame = try observedFrame(element)
    let point = CGPoint(x: frame.midX, y: frame.midY)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        pumpRunLoop(0.15)
    }
}

func hoverObserved(_ element: AXUIElement) throws {
    let frame = try observedFrame(element)
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left) else {
        throw SmokeFailure(description: "Could not create menu hover event")
    }
    event.flags = []
    event.post(tap: .cghidEventTap)
    pumpRunLoop(0.4)
}

func dragObserved(_ element: AXUIElement, by delta: CGSize) throws {
    let frame = try observedFrame(element)
    let start = CGPoint(x: frame.midX, y: frame.midY)
    func post(_ type: CGEventType, at point: CGPoint) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else {
            throw SmokeFailure(description: "Could not create resize drag event")
        }
        event.flags = []
        event.post(tap: .cghidEventTap)
        pumpRunLoop(0.04)
    }
    try post(.mouseMoved, at: start)
    try post(.leftMouseDown, at: start)
    var point = start
    defer { try? post(.leftMouseUp, at: point) }
    for step in 1...12 {
        let fraction = CGFloat(step) / 12
        point = CGPoint(x: start.x + delta.width * fraction, y: start.y + delta.height * fraction)
        try post(.leftMouseDragged, at: point)
    }
}

@discardableResult
func verifyLayout(grid: Bool, itemNames: [String], columns expectedColumns: Int? = nil, in app: AXUIElement) throws -> Int {
    try require(itemNames.count >= 4, "Layout check needs at least the first four fixture names")
    var frames: [CGRect] = []
    var columns = 1
    try require(until(4) {
        frames = itemNames.compactMap { name in
            guard let item = identified("desktop.item.\(name)", in: app) else { return nil }
            return try? observedFrame(item)
        }
        guard frames.count == itemNames.count else { return false }
        if grid {
            columns = frames.prefix { abs($0.minY - frames[0].minY) < 2 }.count
            guard columns >= 2, expectedColumns.map({ columns == $0 }) ?? true else { return false }
            return frames.enumerated().allSatisfy { index, frame in
                guard frame.width > 70, frame.height >= 80, abs(frame.width - frames[0].width) < 2,
                      abs(frame.minX - frames[index % columns].minX) < 2 else { return false }
                if index % columns > 0 {
                    let previous = frames[index - 1]
                    guard abs(frame.minY - previous.minY) < 2, previous.maxX <= frame.minX + 2 else { return false }
                }
                return index < columns || frames[index - columns].maxY <= frame.minY + 2
            }
        }
        return zip(frames, frames.dropFirst()).allSatisfy { previous, next in
            abs(previous.minX - next.minX) < 2 && previous.maxY <= next.minY + 2
        } && frames.allSatisfy { $0.width > 240 && $0.height < 60 }
    }, grid ? "File buttons are not arranged in the expected icon grid" : "File buttons are not arranged in a vertical list")
    return columns
}

func menuBarControl(ownerPIDs: Set<pid_t>, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    let global = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(global, 0.05)
    for screen in NSScreen.screens {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
        let bounds = CGDisplayBounds(number.uint32Value)
        let deadline = Date().addingTimeInterval(1)
        for x in stride(from: bounds.maxX - 6, through: bounds.minX, by: -12) {
            guard Date() < deadline else { break }
            var candidate: AXUIElement?
            if AXUIElementCopyElementAtPosition(global, Float(x), Float(bounds.minY + 12), &candidate) == .success,
               let candidate {
                var pid: pid_t = 0
                AXUIElementGetPid(candidate, &pid)
                if ownerPIDs.contains(pid), predicate(candidate) { return candidate }
            }
        }
    }
    return nil
}

func overflowControl() -> AXUIElement? {
    guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else { return nil }
    let system = AXUIElementCreateApplication(agent.processIdentifier)
    let roots = [system] + [elementValue(system, kAXMenuBarAttribute), elementValue(system, kAXExtrasMenuBarAttribute)].compactMap { $0 }
    if let control = find(roots, maxDepth: 4, matching: { value($0, kAXIdentifierAttribute) as? String == "menu-bar-overflow-indicator" }) {
        return control
    }
    // The menu relay can omit its tree and display overflow on a secondary monitor.
    return menuBarControl(ownerPIDs: [agent.processIdentifier]) {
        value($0, kAXIdentifierAttribute) as? String == "menu-bar-overflow-indicator"
    }
}

func relayedMenuItem(_ app: AXUIElement) -> AXUIElement? {
    var appPID: pid_t = 0
    guard AXUIElementGetPid(app, &appPID) == .success else { return nil }
    var ownerPIDs: Set<pid_t> = [appPID]
    if let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first {
        ownerPIDs.insert(agent.processIdentifier)
    }
    return menuBarControl(ownerPIDs: ownerPIDs) { candidate in
        guard let role = value(candidate, kAXRoleAttribute) as? String,
              [kAXMenuBarItemRole, kAXButtonRole].contains(role) else { return false }
        return [kAXDescriptionAttribute, kAXTitleAttribute].contains {
            (value(candidate, $0) as? String)?.hasPrefix("OneButton ") == true
        }
    }
}

func openMenu(_ app: AXUIElement) throws {
    _ = until(2) { menuItem(app) != nil }
    if menuItem(app) == nil, relayedMenuItem(app) == nil {
        if let bar = elementValue(app, kAXMenuBarAttribute) { try hoverObserved(bar) }
        if menuItem(app) == nil, relayedMenuItem(app) == nil, let overflow = overflowControl() {
            try hoverObserved(overflow)
            // Moving to another monitor can relocate its menu controls; resolve them again before clicking.
            // shortcut: overflow labels match Korean macOS; add variants when testing another locale.
            if let current = overflowControl(),
               value(current, kAXDescriptionAttribute) as? String == "가려진 메뉴 막대 항목 보기" {
                try clickObserved(current)
                pumpRunLoop(0.5)
            }
        }
    }
    var observedItem: AXUIElement?
    try require(until(6) {
        observedItem = menuItem(app) ?? relayedMenuItem(app)
        return observedItem != nil
    }, "OneButton menu item did not appear on any display")
    guard let item = observedItem else { throw SmokeFailure(description: "OneButton menu item disappeared") }
    try hoverObserved(item)
    guard let current = menuItem(app) ?? relayedMenuItem(app) else {
        throw SmokeFailure(description: "OneButton menu item disappeared after moving to its monitor")
    }
    // macOS 27's menu relay acknowledges AXPress without opening this status item.
    try clickObserved(current)
}

func ownedOnscreenWindow(_ pid: pid_t) -> CGWindowID? {
    guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { return nil }
    for entry in entries where entry[kCGWindowOwnerPID as String] as? Int32 == pid {
        guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
              (bounds["Width"] ?? 0) > 200, (bounds["Height"] ?? 0) > 100,
              (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
        return entry[kCGWindowNumber as String] as? CGWindowID
    }
    return nil
}

func observedWindowFrame(_ pid: pid_t) throws -> CGRect {
    guard let windowID = ownedOnscreenWindow(pid),
          let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
          let bounds = entries.first?[kCGWindowBounds as String] as? [String: CGFloat],
          let x = bounds["X"], let y = bounds["Y"],
          let width = bounds["Width"], let height = bounds["Height"] else {
        throw SmokeFailure(description: "App has no observed onscreen window frame")
    }
    return CGRect(x: x, y: y, width: width, height: height)
}

@discardableResult
func resizePopup(by change: CGSize, in app: AXUIElement, pid: pid_t) throws -> CGSize {
    guard let grip = identified("desktop.resize", in: app) else {
        throw SmokeFailure(description: "Popup resize grip is missing")
    }
    let before = try observedWindowFrame(pid)
    let gripFrame = try observedFrame(grip)
    let horizontalDirection: CGFloat = gripFrame.midX < before.midX ? -1 : 1
    try dragObserved(grip, by: CGSize(width: change.width * horizontalDirection, height: change.height))
    var after = before
    try require(until(4) {
        guard let frame = try? observedWindowFrame(pid) else { return false }
        after = frame
        return abs(after.width - before.width - change.width) < 3
            && abs(after.height - before.height - change.height) < 3
    }, "Grip drag did not resize both dimensions: before \(before.size), after \(after.size), requested \(change)")
    return after.size
}

func verifyFolderName(_ name: String, in app: AXUIElement) throws {
    try require(until(3) {
        guard let title = identified("desktop.folder.name", in: app) else { return false }
        return [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].contains {
            value(title, $0) as? String == name
        }
    }, "Popup header does not show the connected folder's actual name")
}

func screenshot(_ pid: pid_t, to url: URL) {
    guard let windowID = ownedOnscreenWindow(pid) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l", String(windowID), url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        if !until(4, { !process.isRunning }) { process.terminate() }
    } catch { /* Optional screenshot; assertions do not depend on capture permission. */ }
}

func closeOpenedFixtureFolder(named name: String) throws {
    var finder: NSRunningApplication?
    var finderAX: AXUIElement?
    try require(until(6) {
        finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        guard let finder else { return false }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        finderAX = application
        guard let window = elementValue(application, kAXFocusedWindowAttribute) else { return false }
        return value(window, kAXTitleAttribute) as? String == name
    }, "NSWorkspace did not open the unique fixture folder in Finder")
    guard let finder, let finderAX,
          let window = elementValue(finderAX, kAXFocusedWindowAttribute),
          value(window, kAXTitleAttribute) as? String == name else {
        throw SmokeFailure(description: "Finder focus changed; fixture tab was left open")
    }
    // Command-W closes only the verified fixture tab, preserving other Finder tabs.
    try key(13, to: finder.processIdentifier, flags: .maskCommand)
    try require(until(3) {
        guard let focused = elementValue(finderAX, kAXFocusedWindowAttribute) else { return true }
        return value(focused, kAXTitleAttribute) as? String != name
    }, "The fixture Finder tab did not close")
    pumpRunLoop(0.5)
}

func closeOpenedFixtureDocument(_ url: URL) throws {
    var editor: NSRunningApplication?
    var editorAX: AXUIElement?
    func isFixtureDocument(_ window: AXUIElement) -> Bool {
        guard let document = value(window, kAXDocumentAttribute) as? String,
              let openedURL = URL(string: document) else { return false }
        return openedURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
    }
    try require(until(6) {
        editor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
        guard let editor else { return false }
        let application = AXUIElementCreateApplication(editor.processIdentifier)
        editorAX = application
        return elementValue(application, kAXFocusedWindowAttribute).map(isFixtureDocument) == true
    }, "The fixture text document did not open in TextEdit")
    guard let editor, let editorAX,
          elementValue(editorAX, kAXFocusedWindowAttribute).map(isFixtureDocument) == true else {
        throw SmokeFailure(description: "TextEdit focus changed; fixture document was left open")
    }
    try key(13, to: editor.processIdentifier, flags: .maskCommand)
    try require(until(3) {
        elementValue(editorAX, kAXFocusedWindowAttribute).map(isFixtureDocument) != true
    }, "The fixture document did not close")
    pumpRunLoop(0.5)
}

final class Smoke {
    let root: URL
    let fixture: URL
    var launched: [NSRunningApplication] = []

    init(root: URL) {
        self.root = root
        fixture = FileManager.default.temporaryDirectory.appendingPathComponent("OneButton-Smoke-\(UUID().uuidString)")
    }

    func launch(_ name: String, arguments: [String] = [], activates: Bool = false) throws -> NSRunningApplication {
        let url = root.appendingPathComponent("build/Build/Products/Debug/\(name).app")
        try require(FileManager.default.fileExists(atPath: url.path), "Missing built app: \(name)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = activates
        configuration.createsNewApplicationInstance = true
        var completed = false
        var application: NSRunningApplication?
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            application = app
            launchError = error
            completed = true
        }
        try require(until(10) { completed }, "Timed out launching \(name)")
        if let launchError { throw launchError }
        guard let application else { throw SmokeFailure(description: "Launch returned no process: \(name)") }
        launched.append(application)
        return application
    }

    func stop(_ app: NSRunningApplication) {
        if !app.isTerminated {
            app.terminate()
            if !until(3, { app.isTerminated }) { app.forceTerminate() }
        }
    }

    func run() throws {
        try require(AXIsProcessTrusted(), "Accessibility permission is unavailable for this executor")
        try require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.onebutton.desktop").isEmpty,
                    "Quit OneButton before running UI smoke checks to avoid duplicate menu items")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let artifacts = root.appendingPathComponent(".test-artifacts")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        defer {
            launched.reversed().forEach(stop)
            try? FileManager.default.removeItem(at: fixture)
        }
        try Data("OneButton test fixture".utf8).write(to: fixture.appendingPathComponent("문서 2.txt"))
        try Data().write(to: fixture.appendingPathComponent(".hidden"))
        let openName = "00 OneButton Open \(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent(openName), withIntermediateDirectories: false)
        let gridNames = (1...5).map { "0\($0) OneButton Grid \(UUID().uuidString.prefix(8))" }
        for name in gridNames {
            try FileManager.default.createDirectory(at: fixture.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let layoutNames = [openName] + gridNames
        let documentURL = fixture.appendingPathComponent("OneButton Smoke \(UUID().uuidString.prefix(8)).txt")
        try Data("OneButton text document smoke test.\n".utf8).write(to: documentURL)

        var process = try launch("OneButton", arguments: ["--ui-testing", "--reset-test-state"])
        var app = AXUIElementCreateApplication(process.processIdentifier)
        try openMenu(app)
        if !until(6, { identified("desktop.connect", in: app) != nil }) {
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-first-failure.png"))
            throw SmokeFailure(description: "First-launch connect button missing")
        }
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-first-launch.png"))
        try key(53, to: process.processIdentifier)
        try require(until(3) { identified("desktop.connect", in: app) == nil }, "Escape did not close the popup")
        try openMenu(app)
        try require(until(4) { identified("desktop.connect", in: app) != nil }, "Popup did not reopen")
        print("PASS: first launch, menu open, Escape, reopen")

        try press(identified("desktop.connect", in: app), "connect")
        try require(until(5) { labeled("연결", in: app) != nil }, "Folder picker did not appear")
        try require(until(3) { NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier },
                    "Folder picker app is not frontmost; no global keyboard input sent")
        try key(5, to: process.processIdentifier, flags: [.maskCommand, .maskShift], system: true)
        pumpRunLoop(0.5)
        var field: AXUIElement?
        try require(until(4) {
            field = elementValue(app, kAXFocusedUIElementAttribute)
            if let field, let role = value(field, kAXRoleAttribute) as? String,
               role == kAXTextFieldRole || role == kAXComboBoxRole { return true }
            field = find(contentRoots(app)) { value($0, kAXRoleAttribute) as? String == kAXTextFieldRole }
            return field != nil
        }, "Go to Folder text field did not appear")
        if let field { try clickObserved(field) }
        try key(0, to: process.processIdentifier, flags: .maskCommand, system: true)
        pumpRunLoop(0.3)
        try typeText(fixture.path)
        let inputMatches = until(3) { field.flatMap { value($0, kAXValueAttribute) as? String } == fixture.path }
        try require(inputMatches,
                    "Go to Folder input does not equal the temporary fixture path; not granting access")
        try key(36, to: process.processIdentifier, system: true)
        pumpRunLoop(0.4)
        try require(until(4) { labeled(fixture.lastPathComponent, in: app) != nil },
                    "Folder picker did not navigate to the temporary fixture; not granting access")
        try require(until(4) { labeled("연결", in: app) != nil }, "Folder picker confirmation missing")
        try press(labeled("연결", in: app), "confirm selected fixture folder")
        try require(until(6) { labeled("연결", in: app) == nil }, "Folder picker did not close")
        try openMenu(app)
        if !until(6, { labeled("문서 2.txt", in: app) != nil }) {
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-connection-failure.png"))
            throw SmokeFailure(description: "Selected folder's file did not appear")
        }
        try require(labeled(".hidden", in: app) == nil, "Hidden file appeared in the list")
        try verifyFolderName(fixture.lastPathComponent, in: app)
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-connected.png"))
        print("PASS: real folder picker grant, connected folder name, file listing, hidden-file exclusion")

        try key(53, to: process.processIdentifier)
        try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "Connected popup did not close")
        try Data().write(to: fixture.appendingPathComponent("새 파일.txt"))
        try openMenu(app)
        if !until(6, { labeled("새 파일.txt", in: app) != nil }) {
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-refresh-failure.png"))
            throw SmokeFailure(description: "Reopen did not refresh added file")
        }
        print("PASS: automatic refresh after reopening")

        try key(36, to: process.processIdentifier)
        try closeOpenedFixtureFolder(named: openName)
        try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "Return-open did not close popup")
        print("PASS: Return opens the fixture folder in Finder")

        try openMenu(app)
        try verifyLayout(grid: false, itemNames: layoutNames, in: app)
        try press(identified("desktop.view.grid", in: app), "icon view")
        try verifyLayout(grid: true, itemNames: layoutNames, columns: 3, in: app)
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-grid.png"))
        // The previous Return opened item 0; down/right/left must select item 3 in the grid.
        for arrow: CGKeyCode in [125, 124, 123] {
            try key(arrow, to: process.processIdentifier)
            pumpRunLoop(0.15)
        }
        try key(36, to: process.processIdentifier)
        try closeOpenedFixtureFolder(named: gridNames[2])
        try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "Grid Return-open did not close popup")
        print("PASS: list-to-grid, three-column tile geometry, grid arrows and Return")

        try openMenu(app)
        try require(until(5) { identified("desktop.resize", in: app) != nil }, "Resize grip did not appear")
        try resizePopup(by: CGSize(width: 160, height: 100), in: app, pid: process.processIdentifier)
        try verifyLayout(grid: true, itemNames: layoutNames, columns: 4, in: app)
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-resize-larger.png"))
        let savedSize = try resizePopup(by: CGSize(width: -60, height: -60), in: app, pid: process.processIdentifier)
        try verifyLayout(grid: true, itemNames: layoutNames, columns: 4, in: app)
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-resize-smaller.png"))
        print("PASS: real grip drags increase/decrease width and height, grid adapts to four columns")

        stop(process)
        process = try launch("OneButton", arguments: ["--ui-testing"])
        app = AXUIElementCreateApplication(process.processIdentifier)
        try openMenu(app)
        if !until(6, { labeled("문서 2.txt", in: app) != nil }) {
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-restore-failure.png"))
            let error = identified("desktop.error", in: app).flatMap { value($0, kAXValueAttribute) as? String }
            throw SmokeFailure(description: "Bookmark did not restore after relaunch: \(error ?? "no visible error")")
        }
        try require(identified("desktop.connect", in: app) == nil, "Relaunch unexpectedly requires a new grant")
        try verifyFolderName(fixture.lastPathComponent, in: app)
        try require(until(4) {
            guard let frame = try? observedWindowFrame(process.processIdentifier) else { return false }
            return abs(frame.width - savedSize.width) < 3 && abs(frame.height - savedSize.height) < 3
        }, "Popup size was not restored after relaunch")
        try verifyLayout(grid: true, itemNames: layoutNames, columns: 4, in: app)
        print("PASS: sandbox bookmark, folder name, popup size and icon-view preference restoration after relaunch")
        try press(identified("desktop.item.\(openName)", in: app), "fixture folder icon")
        try closeOpenedFixtureFolder(named: openName)
        try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "Click-open did not close popup")
        print("PASS: one-click grid icon opens the fixture folder in Finder")
        try openMenu(app)
        try require(until(5) { identified("desktop.item.\(documentURL.lastPathComponent)", in: app) != nil }, "Document row missing")
        try press(identified("desktop.item.\(documentURL.lastPathComponent)", in: app), "fixture text document row")
        try closeOpenedFixtureDocument(documentURL)
        print("PASS: text document opens in TextEdit and its own tab closes")

        try openMenu(app)
        try press(identified("desktop.view.list", in: app), "list view")
        try verifyLayout(grid: false, itemNames: layoutNames, in: app)
        try press(identified("desktop.item.\(openName)", in: app), "fixture folder row")
        try closeOpenedFixtureFolder(named: openName)
        try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "List click-open did not close popup")
        print("PASS: grid-to-list restores the vertical layout and one-click opening")

        let fullscreenURL = root.appendingPathComponent("build/Build/Products/Debug/OneButtonFullscreenFixture.app")
        if FileManager.default.fileExists(atPath: fullscreenURL.path) {
            let host = try launch("OneButtonFullscreenFixture", activates: true)
            let hostAX = AXUIElementCreateApplication(host.processIdentifier)
            try require(until(5) { identified("fixture.fullscreen", in: hostAX) != nil }, "Fullscreen fixture button missing")
            try press(identified("fixture.fullscreen", in: hostAX), "fullscreen fixture toggle")
            try require(until(10) { labeled("전체 화면 테스트 중", in: hostAX) != nil }, "Fixture did not enter fullscreen")
            try require(ownedOnscreenWindow(host.processIdentifier) != nil, "Fullscreen fixture is not on the active Space")
            let hostFrame = try observedWindowFrame(host.processIdentifier)
            let displayBounds = NSScreen.screens.compactMap { screen -> CGRect? in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
                return CGDisplayBounds(number.uint32Value)
            }.first { $0.contains(CGPoint(x: hostFrame.midX, y: hostFrame.midY)) }
            guard let displayBounds,
                  let revealMenu = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                           mouseCursorPosition: CGPoint(x: displayBounds.midX, y: displayBounds.minY + 1),
                                           mouseButton: .left) else {
                throw SmokeFailure(description: "Could not locate the fullscreen fixture's menu bar edge")
            }
            revealMenu.flags = []
            revealMenu.post(tap: .cghidEventTap)
            pumpRunLoop(1)
            try openMenu(app)
            try require(until(6) { labeled("문서 2.txt", in: app) != nil }, "Popup failed above fullscreen fixture")
            try require(ownedOnscreenWindow(host.processIdentifier) != nil, "Opening popup switched away from fullscreen Space")
            try require(ownedOnscreenWindow(process.processIdentifier) != nil, "Popup is not on screen")
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-fullscreen-popup.png"))
            try press(identified("desktop.view.grid", in: app), "icon view above fullscreen")
            try verifyLayout(grid: true, itemNames: layoutNames, columns: 4, in: app)
            try require(ownedOnscreenWindow(host.processIdentifier) != nil, "Changing to grid switched away from fullscreen Space")
            try resizePopup(by: CGSize(width: 40, height: 30), in: app, pid: process.processIdentifier)
            try require(ownedOnscreenWindow(host.processIdentifier) != nil, "Resizing popup switched away from fullscreen Space")
            try verifyLayout(grid: true, itemNames: layoutNames, columns: 4, in: app)
            screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("native-fullscreen-grid.png"))
            try key(53, to: process.processIdentifier)
            try require(until(3) { labeled("문서 2.txt", in: app) == nil }, "Fullscreen popup did not close")
            try require(ownedOnscreenWindow(host.processIdentifier) != nil, "Closing popup switched away from fullscreen Space")
            print("PASS: popup opens, changes layout, resizes and closes without leaving another app's fullscreen Space")
        } else {
            print("SKIP: fullscreen fixture app is not built")
        }
    }
}

setbuf(stdout, nil)

do {
    try require(CommandLine.arguments.count == 2, "usage: swift script/ui_smoke.swift /absolute/project/root")
    try Smoke(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)).run()
    print("Native UI smoke checks completed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
