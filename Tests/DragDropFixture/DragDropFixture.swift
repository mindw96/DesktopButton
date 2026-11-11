import AppKit
import CryptoKit

private struct ReceivedFile: Codable {
    let name: String
    let sha256: String
    let byteCount: Int
}

private struct DropResult: Codable {
    var preflightDenied: Bool
    var drops: [ReceivedFile] = []
    var sourceMasks: [UInt] = []
    var error: String?
}

private final class DropView: NSView {
    var result: DropResult
    let status = NSTextField(wrappingLabelWithString: "")

    init(probe: URL) {
        result = DropResult(preflightDenied: (try? Data(contentsOf: probe)) == nil)
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.systemBlue.cgColor
        layer?.borderWidth = 2
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Drop test files here")
        setAccessibilityIdentifier("fixture.dropzone")
        status.isSelectable = true
        status.setAccessibilityIdentifier("fixture.drop.result")
        publish()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        result.sourceMasks.append(sender.draggingSourceOperationMask.rawValue)
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], urls.count == 1 else {
            result.error = "Drop did not provide exactly one readable file URL"
            publish()
            return false
        }
        do {
            let url = urls[0]
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            result.drops.append(ReceivedFile(name: url.lastPathComponent,
                                            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                            byteCount: data.count))
            result.error = nil
            publish()
            return true
        } catch {
            result.error = "Receiver could not read the dropped file: \((error as NSError).code)"
            publish()
            return false
        }
    }

    private func publish() {
        if let data = try? JSONEncoder().encode(result), let text = String(data: data, encoding: .utf8) {
            status.stringValue = text
        }
    }
}

private final class DragDropDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe" else {
            NSApp.terminate(nil)
            return
        }
        let drop = DropView(probe: URL(fileURLWithPath: CommandLine.arguments[2]))
        let title = NSTextField(labelWithString: "Sandbox file drop receiver")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Drop the temporary test file here. The app has no pre-granted access to the source folder.")
        let stack = NSStackView(views: [title, explanation, drop, drop.status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        drop.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            drop.widthAnchor.constraint(equalToConstant: 520),
            drop.heightAnchor.constraint(equalToConstant: 250),
            drop.status.widthAnchor.constraint(equalToConstant: 520)
        ])
        let window = NSWindow(contentRect: NSRect(x: 60, y: 180, width: 568, height: 510),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Folder In Bar drag receiver"
        window.contentView = stack
        window.setAccessibilityIdentifier("fixture.drop.window")
        if let screen = NSScreen.screens.first {
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 100))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
private enum DragDropFixture {
    static func main() {
        let app = NSApplication.shared
        let delegate = DragDropDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
