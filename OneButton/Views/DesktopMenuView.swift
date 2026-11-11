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
            Button("선택한 파일 열기") { openSelection() }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
        }
        .onExitCommand { dismiss() }
        .alert("설정을 변경하지 못했습니다", isPresented: Binding(
            get: { loginItemController.errorMessage != nil || dockIconController.errorMessage != nil },
            set: { if !$0 { loginItemController.dismissError(); dockIconController.dismissError() } }
        )) {
            Button("확인", role: .cancel) {
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
                Text(store.folderURL?.lastPathComponent ?? "폴더 연결")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.folderURL?.path ?? "연결할 폴더를 선택해 주세요.")
                    .accessibilityIdentifier("desktop.folder.name")
                Text(store.folderURL == nil ? "Folder In Bar" : "\(store.items.count)개 항목")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                layoutButton(.list, symbol: "list.bullet", label: "목록 보기")
                layoutButton(.grid, symbol: "square.grid.2x2", label: "아이콘 보기")
            }
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            if store.isLoading {
                ProgressView().controlSize(.small).accessibilityLabel("목록 불러오는 중")
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("새로고침 (⌘R)")
            .accessibilityLabel("새로고침")
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

    @ViewBuilder
    private var content: some View {
        if !store.hasConnection {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("폴더를 가까이").font(.headline)
                    Text("폴더를 한 번 연결하면\n여기서 파일을 바로 열 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("폴더 연결…") { chooseFolder() }
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
        DesktopLayout.columnCount(for: popoverSize.size.width)
    }

    private func itemButton(_ item: DesktopItem) -> some View {
        Button {
            selection = item.id
            open(item)
        } label: {
            if layout == .list {
                DesktopItemRow(item: item, isOpening: store.openingURL == item.url)
            } else {
                DesktopItemTile(item: item, isOpening: store.openingURL == item.url,
                                isSelected: selection == item.id)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.openingURL != nil || store.isChoosingFolder)
        .id(item.id)
        .help(item.name)
        .accessibilityIdentifier("desktop.item.\(item.name)")
        .accessibilityLabel(item.name)
        .accessibilityHint(item.isDirectory ? "Finder에서 폴더 열기" : "기본 앱으로 파일 열기")
        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
    }

    private var emptyMessage: String {
        if store.isLoading { return "파일 목록을 불러오는 중…" }
        if store.folderURL == nil { return "폴더 연결과 접근 권한을 확인해 주세요." }
        return "폴더에 표시할 파일이 없어요."
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
                .accessibilityLabel("오류 안내 닫기")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if popoverSize.resizesFromLeadingEdge { resizeHandle }
            if store.hasConnection {
                Button("폴더 다시 연결…") { chooseFolder() }
                    .disabled(store.isChoosingFolder || store.openingURL != nil)
                    .accessibilityIdentifier("desktop.reconnect")
            }
            Spacer()
            #if !APP_STORE
            Menu {
                Button("앱 업데이트 확인…") {
                    dismiss()
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                Divider()
                Toggle("자동으로 업데이트 확인", isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.setAutomaticallyChecksForUpdates($0) }
                ))
                Toggle("자동으로 다운로드 및 설치", isOn: Binding(
                    get: { updateController.automaticallyDownloadsUpdates },
                    set: { updateController.setAutomaticallyDownloadsUpdates($0) }
                ))
                .disabled(!updateController.automaticallyChecksForUpdates)
            } label: {
                Text(updateController.availableUpdateVersion == nil ? "앱 업데이트" : "새 버전 있음")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .font(.system(size: 11))
            .fixedSize()
            .help("Folder In Bar 앱 업데이트 및 자동 업데이트 설정")
            .accessibilityLabel("앱 업데이트")
            .accessibilityIdentifier("desktop.updates")
            #endif
            Menu {
                Toggle("Dock에 아이콘 표시", isOn: Binding(
                    get: { dockIconController.showsIcon },
                    set: { dockIconController.setShowsIcon($0) }
                ))
                .accessibilityIdentifier("desktop.show-in-dock")
                Divider()
                Toggle(loginItemController.status == .requiresApproval
                       ? "로그인 시 자동 실행 (승인 필요)" : "로그인 시 자동 실행", isOn: Binding(
                    get: { loginItemController.isRegistered },
                    set: { loginItemController.setEnabled($0) }
                ))
                .disabled(!loginItemController.allowsChanges)
                .accessibilityIdentifier("desktop.login-at-launch")
                if loginItemController.status == .requiresApproval {
                    Text("시스템 설정에서 허용해야 실행됩니다.")
                    Button("로그인 항목 설정 열기…") {
                        dismiss()
                        loginItemController.openSystemSettings()
                    }
                }
                #if APP_STORE
                Divider()
                Link("개인정보 처리방침", destination: URL(string: "https://mindw96.github.io/DesktopButton/privacy.html")!)
                    .accessibilityIdentifier("desktop.privacy")
                Link("도움말 및 문의", destination: URL(string: "https://mindw96.github.io/DesktopButton/support.html")!)
                    .accessibilityIdentifier("desktop.support")
                #endif
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("설정")
            .accessibilityLabel("설정")
            .accessibilityIdentifier("desktop.settings")
            Button("종료") { NSApplication.shared.terminate(nil) }
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
            .help("모서리를 드래그하여 창의 폭과 높이를 조절하세요.")
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
            .accessibilityLabel("창 크기 조절")
            .accessibilityValue("너비 \(Int(popoverSize.size.width)), 높이 \(Int(popoverSize.size.height))")
            .accessibilityIdentifier("desktop.resize")
            .accessibilityAction(named: "너비 늘리기") { adjustSize(width: 40) }
            .accessibilityAction(named: "너비 줄이기") { adjustSize(width: -40) }
            .accessibilityAction(named: "높이 늘리기") { adjustSize(height: 40) }
            .accessibilityAction(named: "높이 줄이기") { adjustSize(height: -40) }
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
    var body: some View {
        HStack(spacing: 10) {
            DesktopFileIcon(item: item, size: 24)
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
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DesktopItemTile: View {
    let item: DesktopItem
    let isOpening: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            DesktopFileIcon(item: item, size: 48)
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
        .frame(maxWidth: .infinity, minHeight: 98, maxHeight: 98)
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
