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
    @State private var selection: URL?
    @FocusState private var gridIsFocused: Bool
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
            header
            Divider()
            if let message = store.errorMessage {
                errorBanner(message)
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: popoverSize.size.width, height: popoverSize.size.height)
        .background {
            Button("Open Selected File") { openSelection() }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
        }
        .onExitCommand { dismiss() }
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
            gridIsFocused = !active && layout == .grid
            if !active {
                resizeStart = nil
                popoverSize.save()
            }
        }
        .onAppear {
            if selection == nil { selection = store.items.first?.id }
        }
        .onChange(of: store.items) { items in
            if !items.contains(where: { $0.id == selection }) {
                selection = items.first?.id
            }
        }
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
                Text(store.folderURL == nil ? "Folder In Bar" : String(localized: "\(store.items.count) items"))
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
            .disabled(!store.hasConnection || store.isLoading || store.isChoosingFolder)
        }
        .padding(16)
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
            set: { if $0 { store.sortCriterion = criterion } }
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
                Group {
                    if layout == .list {
                        List(selection: $selection) {
                            ForEach(store.items) { item in
                                itemButton(item)
                                    .tag(item.id)
                            }
                        }
                        .listStyle(.plain)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                     count: gridColumnCount), spacing: 8) {
                                ForEach(store.items) { item in
                                    itemButton(item)
                                }
                            }
                            .padding(12)
                        }
                        .focusable()
                        .focused($gridIsFocused)
                        .onMoveCommand { moveSelection($0) }
                        .onAppear { gridIsFocused = true }
                    }
                }
                .onChange(of: selection) { url in
                    if let url { scroll.scrollTo(url) }
                }
                .onChange(of: layout) { _ in
                    if let selection { scroll.scrollTo(selection) }
                }
                .onChange(of: gridColumnCount) { _ in
                    if let selection { scroll.scrollTo(selection) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gridColumnCount: Int {
        DesktopLayout.columnCount(for: popoverSize.size.width, iconSize: iconSize)
    }

    private func itemButton(_ item: DesktopItem) -> some View {
        Button {
            selection = item.id
        } label: {
            if layout == .list {
                DesktopItemRow(item: item, isOpening: store.openingURL == item.url,
                               iconSize: iconSize.listSize)
            } else {
                DesktopItemTile(item: item, isOpening: store.openingURL == item.url,
                                isSelected: selection == item.id, iconSize: iconSize.gridSize)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.openingURL != nil || store.isChoosingFolder)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            selection = item.id
            open(item)
        })
        .onDrag {
            selection = item.id
            return store.dragProvider(for: item)
        }
        .id(item.id)
        .help(String(localized: "\(item.name)\nClick once to select, double-click to open, or drag to another app."))
        .accessibilityIdentifier("desktop.item.\(item.name)")
        .accessibilityLabel(item.name)
        .accessibilityHint(item.isDirectory
                           ? String(localized: "Click once to select, or double-click to open in Finder.")
                           : String(localized: "Click once to select, double-click to open, or drag to another app to attach."))
        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
        .accessibilityAction(named: "Open") {
            selection = item.id
            open(item)
        }
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
                    .disabled(store.isChoosingFolder || store.openingURL != nil)
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
        guard let item = store.items.first(where: { $0.id == selection }) else { return }
        open(item)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let current = store.items.firstIndex(where: { $0.id == selection })
        guard let next = layout.selectionIndex(from: current, direction: direction,
                                               itemCount: store.items.count,
                                               columnCount: gridColumnCount) else { return }
        selection = store.items[next].id
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
