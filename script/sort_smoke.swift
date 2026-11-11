// Compiled after existing UI and drag helpers by sort_smoke.sh.
func runSortChecks(root: URL, sourceURL: URL) throws {
    try require(AXIsProcessTrusted(), "Accessibility permission is unavailable")
    try require(NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow",
                "The Mac is locked; no UI input was sent")
    try require(sourceURL.pathComponents.contains("Debug")
                && Bundle(url: sourceURL)?.bundleIdentifier == "com.onebutton.desktop"
                && Bundle(url: sourceURL)?.object(forInfoDictionaryKey: "SUFeedURL") == nil,
                "Use the Store Debug app with isolated test preferences")
    try require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.onebutton.desktop").isEmpty,
                "Quit the existing Folder In Bar instance before this isolated test")
    try requireSandboxed(sourceURL)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolderInBar-Sort-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let names = ["파일 2.txt", "파일 10.txt", "파일 30.txt"]
    let lengths = [20, 10, 30]
    let dates = [3000.0, 1000.0, 2000.0]
    for index in names.indices {
        let file = folder.appendingPathComponent(names[index])
        try Data(repeating: 65 + UInt8(index), count: lengths[index]).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: dates[index])],
                                              ofItemAtPath: file.path)
    }
    let clickedFile = folder.appendingPathComponent(names[0])
    var launched: [NSRunningApplication] = []
    defer {
        if openTestDocumentExists(clickedFile) { try? closeDragFixtureDocument(clickedFile) }
        launched.reversed().forEach(stopDragApp)
        try? FileManager.default.removeItem(at: folder)
    }
    var process = try launchDragApp(sourceURL, arguments: ["--ui-testing", "--reset-test-state"])
    launched.append(process)
    pumpRunLoop(3)
    process.activate(options: [])
    pumpRunLoop(1)
    var app = AXUIElementCreateApplication(process.processIdentifier)
    try openMenu(app)
    try require(until(5) { identified("desktop.connect", in: app) != nil }, "Connect control missing")
    try press(identified("desktop.connect", in: app), "connect test folder")
    try require(until(5) { labeled("연결", in: app) != nil }, "Folder picker missing")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier,
                "Folder picker is not frontmost; no path typed")
    try key(5, to: process.processIdentifier, flags: [.maskCommand, .maskShift], system: true)
    pumpRunLoop(0.5)
    var field: AXUIElement?
    try require(until(4) {
        field = elementValue(app, kAXFocusedUIElementAttribute)
        return field.map { [kAXTextFieldRole, kAXComboBoxRole].contains(value($0, kAXRoleAttribute) as? String ?? "") } == true
    }, "Folder picker path field missing")
    if let field { try clickObserved(field) }
    try key(0, to: process.processIdentifier, flags: .maskCommand, system: true)
    try typeText(folder.path)
    try require(until(3) { field.flatMap { value($0, kAXValueAttribute) as? String } == folder.path },
                "Picker path differs from the temporary test folder")
    try key(36, to: process.processIdentifier, system: true)
    try require(until(4) { labeled(folder.lastPathComponent, in: app) != nil }, "Picker did not show test folder")
    try press(labeled("연결", in: app), "confirm test folder")
    try require(until(5) { labeled("연결", in: app) == nil }, "Folder picker did not close")

    func showFiles() throws {
        if identified("desktop.sort", in: app) == nil { try openMenu(app) }
        try require(until(5) { identified("desktop.item.\(names[0])", in: app) != nil }, "Fixture file missing")
    }
    func choose(_ option: String, date: Bool = false) throws {
        try showFiles()
        try press(identified("desktop.sort", in: app), "sorting menu")
        let labels = ["ascending": "오름차순", "descending": "내림차순", "size": "크기", "modified": "수정일"]
        func optionControl() -> AXUIElement? {
            identified("desktop.sort.\(option)", in: app) ?? labels[option].flatMap { labeled($0, in: app) }
        }
        if date {
            let submenu = identified("desktop.sort.dates", in: app) ?? labeled("날짜", in: app)
            guard let submenu else { throw SmokeFailure(description: "Date submenu missing") }
            try hoverObserved(submenu)
        }
        try require(until(4) { optionControl() != nil }, "Sort option missing: \(option)")
        try press(optionControl(), "sort \(option)")
        pumpRunLoop(0.3)
    }
    var checks: [[String: Any]] = []
    func check(_ title: String, _ indices: [Int], grid: Bool = false) throws {
        try showFiles()
        let expected = indices.map { names[$0] }
        var observed: [String] = []
        try require(until(5) {
            let positioned = names.compactMap { name -> (String, CGRect)? in
                guard let item = identified("desktop.item.\(name)", in: app),
                      let frame = try? observedFrame(item), frame.width > 0, frame.height > 0 else { return nil }
                return (name, frame)
            }
            guard positioned.count == names.count else { return false }
            observed = positioned.sorted {
                abs($0.1.minY - $1.1.minY) < 3 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY
            }.map { $0.0 }
            let rows = Set(positioned.map { Int(($0.1.minY / 5).rounded()) }).count
            return observed == expected && (grid ? rows < names.count : rows == names.count)
        }, "\(title): expected \(expected), observed \(observed)")
        checks.append(["check": title, "order": observed, "layout": grid ? "grid" : "list"])
        print("PASS: \(title)")
    }
    try check("initial natural name order", [0, 1, 2])
    try choose("descending")
    try check("name descending", [2, 1, 0])
    try choose("size")
    try check("size descending", [2, 0, 1])
    try choose("ascending")
    try check("size ascending", [1, 0, 2])
    try choose("modified", date: true)
    try check("modified date ascending", [1, 2, 0])
    try press(identified("desktop.view.grid", in: app), "grid layout")
    try check("same sort in grid", [1, 2, 0], grid: true)
    try choose("descending")
    try check("modified date descending in grid", [0, 2, 1], grid: true)
    try press(identified("desktop.refresh", in: app), "refresh sorted folder")
    pumpRunLoop(1)
    try check("refresh preserves current sorting", [0, 2, 1], grid: true)
    stopDragApp(process)
    process = try launchDragApp(sourceURL, arguments: ["--ui-testing"])
    launched.append(process)
    app = AXUIElementCreateApplication(process.processIdentifier)
    pumpRunLoop(2)
    try check("relaunch restores criterion, direction and grid", [0, 2, 1], grid: true)
    try clickObserved(identified("desktop.item.\(names[0])", in: app)!)
    try closeDragFixtureDocument(clickedFile)
    print("PASS: sorted file still opens with one click; only the fixture tab closed")
    for index in names.indices {
        try require(try Data(contentsOf: folder.appendingPathComponent(names[index]))
                    == Data(repeating: 65 + UInt8(index), count: lengths[index]), "Sorting changed original file bytes")
    }
    let artifacts = root.appendingPathComponent(".test-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: ["checks": checks, "ordinaryClickPassed": true, "originalsPreserved": true],
                               options: [.prettyPrinted, .sortedKeys])
        .write(to: artifacts.appendingPathComponent("sort-smoke-result.json"))
}

setbuf(stdout, nil)
do {
    try require(CommandLine.arguments.count == 3, "usage: script/sort_smoke.sh PROJECT_ROOT STORE_DEBUG_APP")
    try runSortChecks(root: URL(fileURLWithPath: CommandLine.arguments[1]),
                      sourceURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("Native sorting checks completed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
