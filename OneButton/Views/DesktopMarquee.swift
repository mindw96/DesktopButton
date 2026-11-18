import AppKit
import SwiftUI

struct DesktopMarqueeLayout: Equatable {
    let layout: DesktopLayout
    let iconSize: DesktopIconSize
    let columnCount: Int

    var horizontalInset: CGFloat { layout == .list ? 18 : 12 }
    var verticalInset: CGFloat { layout == .list ? 6 : 12 }
    var spacing: CGFloat { layout == .list ? 1 : 8 }
    var rowHeight: CGFloat { layout == .list ? max(30, iconSize.listSize + 6) : iconSize.gridSize + 50 }

    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    func intersectingIndices(_ rect: CGRect, width: CGFloat, itemCount: Int) -> [Int] {
        guard itemCount > 0, !rect.isEmpty else { return [] }
        let columns = layout == .list ? 1 : max(1, columnCount)
        let cellWidth = (width - 2 * horizontalInset - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        guard cellWidth > 0 else { return [] }
        let strideY = rowHeight + spacing
        let firstRow = max(0, Int(floor((rect.minY - verticalInset) / strideY)))
        let lastRow = min((itemCount - 1) / columns, Int(floor((rect.maxY - verticalInset) / strideY)))
        guard firstRow <= lastRow else { return [] }

        return (firstRow * columns ..< min(itemCount, (lastRow + 1) * columns)).filter { index in
            let cell = CGRect(x: horizontalInset + CGFloat(index % columns) * (cellWidth + spacing),
                              y: verticalInset + CGFloat(index / columns) * strideY,
                              width: cellWidth, height: rowHeight)
            return !cell.intersection(rect).isEmpty
        }
    }
}

// Behind the cells, this view receives only background presses. Its coordinates stay
// attached to the scroll document as the clip view moves during a drag.
struct DesktopMarqueeSurface: NSViewRepresentable {
    let layout: DesktopMarqueeLayout
    let items: [DesktopItem]
    @Binding var selection: DesktopSelection
    @Binding var rectangle: CGRect?
    let focusFiles: () -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.actions = self }

    final class Surface: NSView {
        var actions: DesktopMarqueeSurface?
        private var start: CGPoint?
        private var windowPoint = CGPoint.zero
        private var original = DesktopSelection()
        private var initialContent: DesktopMarqueeSurface?
        private var modifiers: NSEvent.ModifierFlags = []
        private var scrolling: Timer?
        private var escapeMonitor: Any?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            finish(cancelled: true)
            guard let actions else { return }
            start = convert(event.locationInWindow, from: nil)
            windowPoint = event.locationInWindow
            initialContent = actions
            original = actions.selection
            modifiers = event.modifierFlags
            actions.focusFiles()
            NotificationCenter.default.addObserver(self, selector: #selector(windowLostFocus(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: window)
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, event.keyCode == 53 else { return event }
                self.finish(cancelled: true)
                return nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let actions else { return }
            windowPoint = event.locationInWindow
            let point = convert(windowPoint, from: nil)
            if actions.rectangle == nil && hypot(point.x - start.x, point.y - start.y) < 4 { return }
            updateRectangle()
            if self.start != nil && scrolling == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scrollAtEdge() }
                }
                RunLoop.main.add(timer, forMode: .common)
                scrolling = timer
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard start != nil, let actions else { return }
            if actions.rectangle != nil {
                windowPoint = event.locationInWindow
                updateRectangle()
            } else if modifiers.intersection([.command, .shift]).isEmpty {
                actions.selection = DesktopSelection()
            }
            finish(cancelled: false)
        }

        @objc private func windowLostFocus(_ notification: Notification) { finish(cancelled: true) }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { finish(cancelled: true) }
            super.viewWillMove(toWindow: newWindow)
        }

        private func updateRectangle() {
            guard let start, let actions, let initialContent else { return }
            guard actions.layout == initialContent.layout, actions.items == initialContent.items else {
                finish(cancelled: true)
                return
            }
            let point = convert(windowPoint, from: nil)
            let end = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                              y: min(max(point.y, bounds.minY), bounds.maxY))
            var rect = DesktopMarqueeLayout.rectangle(from: start, to: end)
            // A horizontal or vertical sweep still covers one point of the other axis.
            rect.size.width = max(1, rect.width)
            rect.size.height = max(1, rect.height)
            guard rect != actions.rectangle else { return }
            actions.rectangle = rect
            let hits = actions.layout.intersectingIndices(rect, width: bounds.width, itemCount: actions.items.count)
            actions.selection = original.marquee(hits: Set(hits.compactMap { actions.items[$0].selectionKey }),
                                                 modifiers: modifiers, in: actions.items)
        }

        private func scrollAtEdge() {
            guard let scroll = enclosingScrollView, window?.isVisible == true else { return }
            let clip = scroll.contentView
            let viewport = convert(clip.bounds, from: clip)
            let point = convert(windowPoint, from: nil)
            let delta: CGFloat
            if point.y > viewport.maxY - 22 {
                delta = min(20, point.y - viewport.maxY + 22)
            } else if point.y < viewport.minY + 22 {
                delta = -min(20, viewport.minY + 22 - point.y)
            } else { return }
            var proposed = clip.bounds
            proposed.origin.y += clip.isFlipped ? delta : -delta
            let next = clip.constrainBoundsRect(proposed)
            guard next.origin != clip.bounds.origin else { return }
            clip.scroll(to: next.origin)
            scroll.reflectScrolledClipView(clip)
            updateRectangle()
        }

        private func finish(cancelled: Bool) {
            guard start != nil else { return }
            start = nil
            initialContent = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            scrolling?.invalidate()
            scrolling = nil
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            guard let actions, actions.rectangle != nil else { return }
            if cancelled {
                var restored = original
                restored.reconcile(with: actions.items)
                actions.selection = restored
            }
            actions.rectangle = nil
        }
    }
}
