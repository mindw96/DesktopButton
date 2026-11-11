// Compiled after existing UI and drag helpers by localization_smoke.sh.
func runLocalizationChecks(root: URL, sourceURL: URL) throws {
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
    let artifacts = root.appendingPathComponent(".test-artifacts")
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    var results: [[String: Any]] = []
    for language in ["en", "ko"] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolderInBar-Language-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let document = folder.appendingPathComponent("문서 10 & notes.txt")
        let second = folder.appendingPathComponent("Sample 2.txt")
        let original = Data("Folder In Bar localization fixture.\n".utf8)
        let process = try launchDragApp(sourceURL, arguments: ["--ui-testing", "--reset-test-state",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "ko_KR"])
        defer {
            if openTestDocumentExists(document) { try? closeDragFixtureDocument(document) }
            stopDragApp(process)
            try? FileManager.default.removeItem(at: folder)
        }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        func text(_ english: String, _ korean: String) -> String { language == "en" ? english : korean }
        func expect(_ english: String, _ korean: String) throws {
            let label = text(english, korean)
            try require(until(4) { labeled(label, in: app) != nil }, "\(language): missing translated label: \(label)")
        }
        func showPanel() throws {
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
            try require(until(5) { identified("desktop.sort", in: app) != nil }, "Localized popup missing")
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
        try showPanel()
        try expect("Connect Folder", "폴더 연결")
        try expect("Your Folder at Hand", "폴더를 가까이")
        try expect("Connect Folder…", "폴더 연결…")
        try expect("List View", "목록 보기")
        try expect("Grid View", "아이콘 보기")
        try expect("Refresh", "새로고침")
        try expect("Settings", "설정")
        try expect("Quit", "종료")
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("localization-\(language)-onboarding.png"))
        print("PASS \(language): onboarding and toolbar labels")

        try press(identified("desktop.sort", in: app), "localized sort menu")
        for pair in [("Name", "이름"), ("Kind", "종류"), ("Size", "크기"), ("Tags", "태그"),
                     ("Application", "응용 프로그램"), ("Ascending", "오름차순"), ("Descending", "내림차순")] {
            try expect(pair.0, pair.1)
        }
        guard let dates = identified("desktop.sort.dates", in: app) ?? labeled(text("Date", "날짜"), in: app) else {
            throw SmokeFailure(description: "Localized Date submenu missing")
        }
        try hoverObserved(dates)
        for pair in [("Date Last Opened", "최근 사용일"), ("Date Added", "추가된 날짜"),
                     ("Date Modified", "수정일"), ("Date Created", "생성일")] { try expect(pair.0, pair.1) }
        try press(identified("desktop.sort.modified", in: app) ?? labeled(text("Date Modified", "수정일"), in: app),
                  "select localized date sorting")
        try require(until(3) { labeled(text("Date Modified", "수정일"), in: app) == nil }, "Date menu did not close")
        pumpRunLoop(0.3)
        try showPanel()
        try press(identified("desktop.settings", in: app), "localized settings")
        try expect("Show Icon in Dock", "Dock에 아이콘 표시")
        try expect("Launch at Login", "로그인 시 자동 실행")
        try expect("Privacy Policy", "개인정보 처리방침")
        try expect("Help & Support", "도움말 및 문의")
        guard let size = identified("desktop.icon-size", in: app) ?? labeled(text("Icon Size", "아이콘 크기"), in: app) else {
            throw SmokeFailure(description: "Localized Icon Size submenu missing")
        }
        try hoverObserved(size)
        for pair in [("Small", "작게"), ("Medium", "보통"), ("Large", "크게")] { try expect(pair.0, pair.1) }
        try press(identified("desktop.icon-size.large", in: app) ?? labeled(text("Large", "크게"), in: app), "large icons")
        try require(until(3) { labeled(text("Large", "크게"), in: app) == nil }, "Icon size menu did not close")
        pumpRunLoop(0.3)
        try showPanel()
        print("PASS \(language): sort/date, settings and icon size menus")

        try press(identified("desktop.connect", in: app), "connect isolated empty folder")
        try expect("Connect", "연결")
        try expect("Choose a folder to connect. Its files will appear here so you can open them.",
                   "연결할 폴더를 선택해 주세요. 파일 목록을 표시하고 선택한 파일을 엽니다.")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier,
                    "Folder picker is not frontmost; no path typed")
        try key(5, to: process.processIdentifier, flags: [.maskCommand, .maskShift], system: true)
        pumpRunLoop(0.5)
        var field: AXUIElement?
        try require(until(4) {
            field = elementValue(app, kAXFocusedUIElementAttribute)
            return field.map { [kAXTextFieldRole, kAXComboBoxRole].contains(value($0, kAXRoleAttribute) as? String ?? "") } == true
        }, "Picker path field missing")
        if let field { try clickObserved(field) }
        try key(0, to: process.processIdentifier, flags: .maskCommand, system: true)
        pumpRunLoop(0.2)
        try typeText(folder.path)
        try require(until(3) { field.flatMap { value($0, kAXValueAttribute) as? String } == folder.path }, "Unexpected picker path")
        try key(36, to: process.processIdentifier, system: true)
        try require(until(4) { labeled(folder.lastPathComponent, in: app) != nil }, "Picker did not navigate to fixture")
        try press(labeled(text("Connect", "연결"), in: app), "confirm isolated folder")
        try require(until(5) { labeled(text("Connect", "연결"), in: app) == nil }, "Picker did not close")
        try showPanel()
        try expect("0 items", "0개 항목")
        try verifyFolderName(folder.lastPathComponent, in: app)
        try expect("Reconnect Folder…", "폴더 다시 연결…")
        for (file, count) in [(document, 1), (second, 2)] {
            try original.write(to: file)
            try press(identified("desktop.refresh", in: app), "refresh localized file count")
            try expect(count == 1 ? "1 item" : "2 items", "\(count)개 항목")
            try expect(file.lastPathComponent, file.lastPathComponent)
        }
        screenshot(process.processIdentifier, to: artifacts.appendingPathComponent("localization-\(language)-files.png"))
        print("PASS \(language): folder picker, raw filenames, zero/one/multiple counts")

        for layout in ["list", "grid"] {
            try showPanel()
            try press(identified("desktop.view.\(layout)", in: app), "localized \(layout) view")
            try require(until(3) { identified("desktop.item.\(document.lastPathComponent)", in: app) != nil }, "Fixture missing")
            try clickObserved(identified("desktop.item.\(document.lastPathComponent)", in: app)!)
            pumpRunLoop(NSEvent.doubleClickInterval + 0.2)
            try require(!openTestDocumentExists(document), "Single click unexpectedly opened fixture")
            var item = identified("desktop.item.\(document.lastPathComponent)", in: app)!
            var selected = false
            for _ in 0..<4 {
                if value(item, kAXSelectedAttribute) as? Bool == true { selected = true; break }
                guard let parent = elementValue(item, kAXParentAttribute) else { break }
                item = parent
            }
            try require(selected, "Single click did not select fixture")
            try doubleClickObserved(identified("desktop.item.\(document.lastPathComponent)", in: app)!)
            try closeDragFixtureDocument(document)
            try require(until(3) { identified("desktop.sort", in: app) == nil }, "Double-click did not close popup")
        }
        for file in [document, second] { try require(try Data(contentsOf: file) == original, "Fixture content changed") }
        results.append(["language": language, "menus": true, "picker": true, "pluralCounts": true,
                        "rawNamesPreserved": true, "singleAndDoubleClicks": true, "originalsPreserved": true])
        print("PASS \(language): list/grid single selection, double opening, original preservation")
    }
    try JSONSerialization.data(withJSONObject: ["checks": results, "systemLanguageChanged": false],
                               options: [.prettyPrinted, .sortedKeys])
        .write(to: artifacts.appendingPathComponent("localization-smoke-result.json"))
}

setbuf(stdout, nil)
do {
    try require(CommandLine.arguments.count == 3, "usage: script/localization_smoke.sh PROJECT_ROOT STORE_DEBUG_APP")
    try runLocalizationChecks(root: URL(fileURLWithPath: CommandLine.arguments[1]),
                              sourceURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("Native English/Korean localization checks completed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
