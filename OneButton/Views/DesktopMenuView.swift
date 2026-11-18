import AppKit
import SwiftUI

struct DesktopMenuView: View {
    @ObservedObject var store: DesktopStore
    #if !APP_STORE
    @ObservedObject var updateController: UpdateController
    #endif
    @ObservedObject var loginItemController: LoginItemController
    @ObservedObject var dockIconController: DockIconController
    @ObservedObject var popoverSize: PopoverSize
    let dismiss: () -> Void
    @State private var selection = DesktopSelection()
    @State private var marqueeRect: CGRect?
    @State private var pendingTrash: [DesktopItem] = []
    @FocusState private var filesAreFocused: Bool
    @AppStorage private var layout: DesktopLayout
    @AppStorage private var iconSize: DesktopIconSize
    @State private var resizeStart: (point: CGPoint, size: CGSize)?
    @GestureState private var isResizing = false

    #if APP_STORE
    init(store: DesktopStore, loginItemController: LoginItemController,
         dockIconController: DockIconController,
         popoverSize: PopoverSize,
         defaults: UserDefaults = .standard, dismiss: @escaping () -> Void) {
        self.store = store
        self.loginItemController = loginItemController
        self.dockIconController = dockIconController
        self.popoverSize = popoverSize
        self.dismiss = dismiss
        _layout = AppStorage(wrappedValue: .list, "desktopLayout", store: defaults)
        _iconSize = AppStorage(wrappedValue: .medium, "desktopIconSize", store: defaults)
    }
    #else
    init(store: DesktopStore, updateController: UpdateController, loginItemController: LoginItemController,
         dockIconController: DockIconController,
         popoverSize: PopoverSize,
         defaults: UserDefaults = .standard, dismiss: @escaping () -> Void) {
        self.store = store
        self.updateController = updateController
        self.loginItemController = loginItemController
        self.dockIconController = dockIconController
        self.popoverSize = popoverSize
        self.dismiss = dismiss
        _layout = AppStorage(wrappedValue: .list, "desktopLayout", store: defaults)
        _iconSize = AppStorage(wrappedValue: .medium, "desktopIconSize", store: defaults)
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if pendingTrash.isEmpty {
                header
                Divider()
                if let message = store.errorMessage {
                    errorBanner(message)
                    Divider()
                }
                content
                Divider()
                footer
            } else {
                trashConfirmation
            }
        }
        .frame(width: popoverSize.size.width, height: popoverSize.size.height)
        .background {
            if pendingTrash.isEmpty && !store.items.isEmpty && canInteract {
                ZStack {
                    Button("Open Selected File") { openSelection() }
                        .keyboardShortcut(.defaultAction)
                    Button("Select All") { selection.selectAll(in: store.items) }
                        .keyboardShortcut("a", modifiers: .command)
                }
                .hidden()
                .accessibilityHidden(true)
            }
        }
        .onExitCommand {
            if pendingTrash.isEmpty { dismiss() } else { pendingTrash = [] }
        }
        .alert("Unable to Change Settings", isPresented: Binding(
            get: { loginItemController.errorMessage != nil || dockIconController.errorMessage != nil },
            set: { if !$0 { loginItemController.dismissError(); dockIconController.dismissError() } }
        )) {
            Button("OK", role: .cancel) {
                loginItemController.dismissError()
                dockIconController.dismissError()
            }
        } message: {
            Text(dockIconController.errorMessage ?? loginItemController.errorMessage ?? "")
        }
        .onMoveCommand { direction in moveSelection(direction) }
        .onChange(of: isResizing) { active in
            filesAreFocused = !active
            if !active {
                resizeStart = nil
                popoverSize.save()
            }
        }
        .onChange(of: store.folderURL) { _ in
            selection = DesktopSelection()
            if let first = store.items.first { selection.select(first, modifiers: [], in: store.items) }
        }
        .onChange(of: store.items) { selection.reconcile(with: $0) }
        .onDisappear { pendingTrash = [] }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.folderURL?.lastPathComponent ?? String(localized: "Connect Folder"))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.folderURL?.path ?? String(localized: "Choose a folder to connect."))
                    .accessibilityIdentifier("desktop.folder.name")
                Text(folderSubtitle)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                layoutButton(.list, symbol: "list.bullet", label: String(localized: "List View"))
                layoutButton(.grid, symbol: "square.grid.2x2", label: String(localized: "Grid View"))
            }
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            sortMenu
            if store.hasConnection {
                Button { requestTrash() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Move to Trash…")
                    .accessibilityLabel("Move to Trash…")
                    .accessibilityIdentifier("desktop.trash")
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(selection.ids.isEmpty || !canInteract)
            }
            if store.isLoading {
                ProgressView().controlSize(.small).accessibilityLabel("Loading Files")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("desktop.refresh")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!store.hasConnection || store.isLoading || store.isChoosingFolder || store.isTrashing)
        }
        .padding(16)
    }

    private var folderSubtitle: String {
        if selection.ids.count > 1 { return String(localized: "\(selection.ids.count) selected") }
        if store.folderURL == nil { return "Folder In Bar" }
        return String(localized: "\(store.items.count) items")
    }

    private func layoutButton(_ value: DesktopLayout, symbol: String, label: String) -> some View {
        Button {
            layout = value
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .background(layout == value ? Color.primary.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("desktop.view.\(value.rawValue)")
        .accessibilityAddTraits(layout == value ? .isSelected : [])
    }

    private var sortMenu: some View {
        Menu {
            ForEach([DesktopSort.name, .kind, .size], id: \.self) { sortOption($0) }
            Menu("Date") {
                ForEach(DesktopSort.allCases.filter(\.isDate), id: \.self) { sortOption($0) }
            }
            .accessibilityIdentifier("desktop.sort.dates")
            ForEach([DesktopSort.tags, .application], id: \.self) { sortOption($0) }
            Divider()
            Picker("Sort Direction", selection: $store.sortDirection) {
                ForEach(DesktopSortDirection.allCases, id: \.self) { direction in
                    Text(direction.title)
                        .tag(direction)
                        .accessibilityIdentifier("desktop.sort.\(direction.rawValue)")
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Sort: \(store.sortCriterion.title) · \(store.sortDirection.title)\nItems with missing information appear last."))
        .accessibilityLabel("Sort")
        .accessibilityValue("\(store.sortCriterion.title), \(store.sortDirection.title)")
        .accessibilityIdentifier("desktop.sort")
    }

    private func sortOption(_ criterion: DesktopSort) -> some View {
        Toggle(criterion.title, isOn: Binding(
            get: { store.sortCriterion == criterion },
            set: { if $0 { Task { await store.setSortCriterion(criterion) } } }
        ))
        .accessibilityIdentifier("desktop.sort.\(criterion.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasConnection {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Your Folder at Hand").font(.headline)
                    Text("Connect a folder once to open\nits files right here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Connect Folder…") { chooseFolder() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isChoosingFolder)
                        .accessibilityIdentifier("desktop.connect")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.folderURL != nil ? "tray" : "folder.badge.questionmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(emptyMessage).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scroll in
                GeometryReader { viewport in
                    ScrollView {
                        Group {
                            if layout == .list {
                                LazyVStack(spacing: fileLayout.spacing) {
                                    ForEach(store.items) { item in itemButton(item) }
                                }
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: fileLayout.spacing),
                                                         count: gridColumnCount), spacing: fileLayout.spacing) {
                                    ForEach(store.items) { item in itemButton(item) }
                                }
                            }
                        }
                        .padding(.horizontal, fileLayout.horizontalInset)
                        .padding(.vertical, fileLayout.verticalInset)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                        .background {
                            DesktopMarqueeSurface(layout: fileLayout, items: store.items,
                                                  selection: $selection, rectangle: $marqueeRect,
                                                  focusFiles: { filesAreFocused = true })
                                .allowsHitTesting(canInteract)
                                .accessibilityHidden(true)
                        }
                        .overlay(alignment: .topLeading) {
                            if let rect = marqueeRect {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1) }
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .focusable()
                    .focused($filesAreFocused)
                    .onMoveCommand { moveSelection($0) }
                    .onAppear { filesAreFocused = true }
                    .onChange(of: selection.lead?.url) { url in
                        if marqueeRect == nil, let url { scroll.scrollTo(url) }
                    }
                    .onChange(of: layout) { _ in
                        if let url = selection.lead?.url { scroll.scrollTo(url) }
                    }
                    .onChange(of: gridColumnCount) { _ in
                        if let url = selection.lead?.url { scroll.scrollTo(url) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gridColumnCount: Int {
        DesktopLayout.columnCount(for: popoverSize.size.width, iconSize: iconSize)
    }

    private var fileLayout: DesktopMarqueeLayout {
        DesktopMarqueeLayout(layout: layout, iconSize: iconSize, columnCount: gridColumnCount)
    }

    private var canInteract: Bool {
        store.openingURL == nil && !store.isChoosingFolder && !store.isTrashing
    }

    private func itemButton(_ item: DesktopItem) -> some View {
        let selected = selection.contains(item)
        return Button {
            select(item, modifiers: [])
        } label: {
            if layout == .list {
                DesktopItemRow(item: item, isOpening: store.openingURL == item.url,
                               iconSize: iconSize.listSize)
                    .frame(height: fileLayout.rowHeight)
                    .padding(.horizontal, 6)
                    .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
            } else {
                DesktopItemTile(item: item, isOpening: store.openingURL == item.url,
                                isSelected: selected, iconSize: iconSize.gridSize)
            }
        }
        .buttonStyle(.plain)
        .overlay {
            FilePointerSurface(
                clicked: { modifiers, count in
                    select(item, modifiers: modifiers)
                    if count == 2 && modifiers.intersection([.command, .shift]).isEmpty { open(item) }
                },
                dragURLs: { modifiers in
                    if !selection.contains(item) { select(item, modifiers: modifiers) }
                    guard selection.contains(item) else { return [] }
                    return store.dragURLs(for: selectedItems)
                },
                showContext: {
                    if !selection.contains(item) { select(item, modifiers: []) }
                },
                requestTrash: { if selection.contains(item) { requestTrash() } }
            )
            .id(item.selectionKey)
            .accessibilityHidden(true)
        }
        .disabled(!canInteract || item.selectionKey == nil)
        .id(item.id)
        .help(String(localized: "\(item.name)\nDrag from empty space to select items. Drag selected items to another app."))
        .accessibilityIdentifier("desktop.item.\(item.name)")
        .accessibilityLabel(item.name)
        .accessibilityHint(item.isDirectory
                           ? String(localized: "Click once to select, or double-click to open in Finder.")
                           : String(localized: "Click once to select, double-click to open, or drag to another app to attach."))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Open") { open(item) }
        .accessibilityAction(named: selected ? Text("Remove from Selection") : Text("Add to Selection")) {
            select(item, modifiers: .command)
        }
        .accessibilityAction(named: "Move to Trash…") {
            if !selected { select(item, modifiers: []) }
            requestTrash()
        }
    }

    private var selectedItems: [DesktopItem] {
        let current = store.items.filter(selection.contains)
        return current.count == selection.ids.count ? current : []
    }

    private func select(_ item: DesktopItem, modifiers: NSEvent.ModifierFlags) {
        guard canInteract else { return }
        filesAreFocused = true
        selection.select(item, modifiers: modifiers, in: store.items)
    }

    private func requestTrash() {
        guard canInteract, marqueeRect == nil else { return }
        pendingTrash = selectedItems
    }

    private var trashConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash").font(.title).accessibilityHidden(true)
            Text(pendingTrash.count == 1
                 ? String(localized: "Move “\(pendingTrash[0].name)” to the Trash?")
                 : String(localized: "Move \(pendingTrash.count) items to the Trash?"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .truncationMode(.middle)
            HStack {
                Button("Cancel") { pendingTrash = [] }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("desktop.trash.cancel")
                Button("Move to Trash", role: .destructive) {
                    let confirmed = pendingTrash
                    pendingTrash = []
                    Task { await store.moveToTrash(confirmed) }
                }
                .accessibilityIdentifier("desktop.trash.confirm")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if store.isLoading { return String(localized: "Loading files…") }
        if store.folderURL == nil { return String(localized: "Check the folder connection and access permission.") }
        return String(localized: "There are no files to display in this folder.")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(3)
                .help(message)
                .accessibilityLabel(message)
                .accessibilityIdentifier("desktop.error")
            Spacer(minLength: 0)
            Button { store.dismissError() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss Error")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if popoverSize.resizesFromLeadingEdge { resizeHandle }
            if store.hasConnection {
                Button("Reconnect Folder…") { chooseFolder() }
                    .disabled(!canInteract)
                    .accessibilityIdentifier("desktop.reconnect")
            }
            Spacer()
            #if !APP_STORE
            Menu {
                Button("Check for Updates…") {
                    dismiss()
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                Divider()
                Toggle("Automatically Check for Updates", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                Toggle("Automatically Download and Install", isOn: Binding(
                    get: { updateController.automaticallyDownloadsUpdates },
                    set: { updateController.setAutomaticallyDownloadsUpdates($0) }
                ))
                .disabled(!updateController.automaticallyChecksForUpdates)
            } label: {
                Text(updateController.availableUpdateVersion == nil ? String(localized: "App Updates") : String(localized: "Update Available"))
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .font(.system(size: 11))
            .fixedSize()
            .help("Folder In Bar updates and automatic update settings")
            .accessibilityLabel("App Updates")
            .accessibilityIdentifier("desktop.updates")
            #endif
            Menu {
                Menu("Icon Size") {
                    ForEach(DesktopIconSize.allCases, id: \.self) { size in
                        Toggle(size.title, isOn: Binding(
                            get: { iconSize == size },
                            set: { if $0 { iconSize = size } }
                        ))
                        .accessibilityIdentifier("desktop.icon-size.\(size.rawValue)")
                    }
                }
                .accessibilityIdentifier("desktop.icon-size")
                Divider()
                Toggle("Show Icon in Dock", isOn: Binding(
                    get: { dockIconController.showsIcon },
                    set: { dockIconController.setShowsIcon($0) }
                ))
                .accessibilityIdentifier("desktop.show-in-dock")
                Divider()
                Toggle(loginItemController.status == .requiresApproval
                       ? String(localized: "Launch at Login (Approval Required)") : String(localized: "Launch at Login"), isOn: Binding(
                    get: { loginItemController.isRegistered },
                    set: { loginItemController.setEnabled($0) }
                ))
                .disabled(!loginItemController.allowsChanges)
                .accessibilityIdentifier("desktop.login-at-launch")
                if loginItemController.status == .requiresApproval {
                    Text("Allow this app in System Settings to launch at login.")
                    Button("Open Login Item Settings…") {
                        dismiss()
                        loginItemController.openSystemSettings()
                    }
                }
                #if APP_STORE
                Divider()
                Link("Privacy Policy", destination: URL(string: "https://mindw96.github.io/DesktopButton/privacy.html")!)
                    .accessibilityIdentifier("desktop.privacy")
                Link("Help & Support", destination: URL(string: "https://mindw96.github.io/DesktopButton/support.html")!)
                    .accessibilityIdentifier("desktop.support")
                #endif
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("desktop.settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityIdentifier("desktop.quit")
            if !popoverSize.resizesFromLeadingEdge { resizeHandle }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var resizeHandle: some View {
        Image(systemName: popoverSize.resizesFromLeadingEdge
              ? "arrow.up.right.and.arrow.down.left" : "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help("Drag the corner to adjust the window width and height.")
            .gesture(DragGesture(minimumDistance: 0)
                .updating($isResizing) { _, active, _ in active = true }
                .onChanged { _ in
                    // Screen coordinates stay stable while the popover repositions itself.
                    if resizeStart == nil { resizeStart = (NSEvent.mouseLocation, popoverSize.size) }
                    guard let start = resizeStart else { return }
                    popoverSize.resize(to: PopoverSize.draggedSize(
                        from: start.size, start: start.point, current: NSEvent.mouseLocation,
                        fromLeadingEdge: popoverSize.resizesFromLeadingEdge
                    ))
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resize Window")
            .accessibilityValue(String(localized: "Width \(Int(popoverSize.size.width)), height \(Int(popoverSize.size.height))"))
            .accessibilityIdentifier("desktop.resize")
            .accessibilityAction(named: "Increase Width") { adjustSize(width: 40) }
            .accessibilityAction(named: "Decrease Width") { adjustSize(width: -40) }
            .accessibilityAction(named: "Increase Height") { adjustSize(height: 40) }
            .accessibilityAction(named: "Decrease Height") { adjustSize(height: -40) }
    }

    private func adjustSize(width: CGFloat = 0, height: CGFloat = 0) {
        popoverSize.resize(to: CGSize(width: popoverSize.size.width + width,
                                     height: popoverSize.size.height + height))
        popoverSize.save()
    }

    private func chooseFolder() {
        dismiss()
        Task { await store.chooseFolder() }
    }

    private func open(_ item: DesktopItem) {
        Task {
            if await store.open(item) { dismiss() }
        }
    }

    private func openSelection() {
        guard canInteract, pendingTrash.isEmpty, marqueeRect == nil, selection.ids.count == 1, let item = selectedItems.first else { return }
        open(item)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard canInteract, pendingTrash.isEmpty, marqueeRect == nil else { return }
        let current = selection.lead.flatMap { lead in store.items.firstIndex { $0.selectionKey == lead } }
        guard let next = layout.selectionIndex(from: current, direction: direction,
                                               itemCount: store.items.count,
                                               columnCount: gridColumnCount) else { return }
        select(store.items[next], modifiers: NSEvent.modifierFlags.intersection(.shift))
    }
}

private struct DesktopItemRow: View {
    let item: DesktopItem
    let isOpening: Bool
    let iconSize: CGFloat
    var body: some View {
        HStack(spacing: 10) {
            DesktopFileIcon(item: item, size: iconSize)
            Text(item.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if isOpening {
                ProgressView().controlSize(.small)
            } else if item.isDirectory {
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: max(30, iconSize + 6), alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DesktopItemTile: View {
    let item: DesktopItem
    let isOpening: Bool
    let isSelected: Bool
    let iconSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            DesktopFileIcon(item: item, size: iconSize)
                .overlay {
                    if isOpening { ProgressView().controlSize(.small) }
                }
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: iconSize + 50, maxHeight: iconSize + 50)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct DesktopFileIcon: View {
    let item: DesktopItem
    let size: CGFloat
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: item.isDirectory ? "folder" : "doc").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: item.url) { icon = NSWorkspace.shared.icon(forFile: item.url.path) }
    }
}

struct DesktopSelection {
    private(set) var ids: Set<FileSelectionKey> = []
    private(set) var lead: FileSelectionKey?
    private var anchor: FileSelectionKey?

    func contains(_ item: DesktopItem) -> Bool {
        item.selectionKey.map(ids.contains) == true
    }

    mutating func select(_ item: DesktopItem, modifiers: NSEvent.ModifierFlags, in items: [DesktopItem]) {
        guard let id = item.selectionKey else { return }
        if modifiers.contains(.shift), let anchor,
           let start = items.firstIndex(where: { $0.selectionKey == anchor }),
           let end = items.firstIndex(where: { $0.selectionKey == id }) {
            let range = items[min(start, end)...max(start, end)].compactMap(\.selectionKey)
            if modifiers.contains(.command) { ids.formUnion(range) } else { ids = Set(range) }
            lead = id
        } else if modifiers.contains(.command), ids.remove(id) != nil {
            lead = items.first(where: contains)?.selectionKey
            anchor = lead
        } else {
            if modifiers.contains(.command) { ids.insert(id) } else { ids = [id] }
            anchor = id
            lead = id
        }
    }

    func marquee(hits: Set<FileSelectionKey>, modifiers: NSEvent.ModifierFlags, in items: [DesktopItem]) -> DesktopSelection {
        var result = self
        if modifiers.contains(.command) { result.ids.formSymmetricDifference(hits) }
        else if modifiers.contains(.shift) { result.ids.formUnion(hits) }
        else { result.ids = hits }
        result.restoreLeadAndAnchor(in: items)
        return result
    }

    mutating func selectAll(in items: [DesktopItem]) {
        ids = Set(items.compactMap(\.selectionKey))
        restoreLeadAndAnchor(in: items)
        anchor = lead
    }

    mutating func reconcile(with items: [DesktopItem]) {
        ids.formIntersection(items.compactMap(\.selectionKey))
        restoreLeadAndAnchor(in: items)
    }

    private mutating func restoreLeadAndAnchor(in items: [DesktopItem]) {
        if lead.map(ids.contains) != true { lead = ids.isEmpty ? nil : items.first(where: contains)?.selectionKey }
        if anchor.map(ids.contains) != true { anchor = lead }
    }
}

// SwiftUI's onDrag exposes a single provider. AppKit publishes a separate file URL per selection.
struct FilePointerSurface: NSViewRepresentable {
    let clicked: (NSEvent.ModifierFlags, Int) -> Void
    let dragURLs: (NSEvent.ModifierFlags) -> [URL]
    let showContext: () -> Void
    let requestTrash: () -> Void

    func makeNSView(context: Context) -> PointerView { PointerView() }
    func updateNSView(_ view: PointerView, context: Context) { view.actions = self }

    static func draggingItems(for urls: [URL], at point: NSPoint) -> [NSDraggingItem] {
        let frame = NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
        return urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // Show three icons in the pile while publishing a file URL for every item.
            let image = index < 3 ? NSWorkspace.shared.icon(forFile: url.path) : nil
            item.setDraggingFrame(frame, contents: image)
            return item
        }
    }

    final class PointerView: NSView, NSDraggingSource {
        var actions: FilePointerSurface?
        private var press: NSEvent?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { press = event }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { press = nil }
            super.viewWillMove(toWindow: newWindow)
        }

        override func mouseUp(with event: NSEvent) {
            guard let press else { return }
            self.press = nil
            if bounds.contains(convert(event.locationInWindow, from: nil)) {
                actions?.clicked(press.modifierFlags, press.clickCount)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let press else { return }
            let start = press.locationInWindow
            let current = event.locationInWindow
            guard hypot(current.x - start.x, current.y - start.y) >= 4 else { return }
            self.press = nil
            guard let urls = actions?.dragURLs(press.modifierFlags), !urls.isEmpty else { return }
            let draggingItems = FilePointerSurface.draggingItems(for: urls, at: convert(current, from: nil))
            let session = beginDraggingSession(with: draggingItems, event: event, source: self)
            session.draggingFormation = .pile
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        override func menu(for event: NSEvent) -> NSMenu? {
            actions?.showContext()
            let menu = NSMenu()
            let trash = menu.addItem(withTitle: String(localized: "Move to Trash…"),
                                     action: #selector(requestTrash), keyEquivalent: "")
            trash.target = self
            return menu
        }

        @objc private func requestTrash() {
            guard window != nil else { return }
            actions?.requestTrash()
        }
    }
}
