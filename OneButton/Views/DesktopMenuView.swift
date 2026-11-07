import AppKit
import SwiftUI

struct DesktopMenuView: View {
    @ObservedObject var store: DesktopStore
    @ObservedObject var updateController: UpdateController
    let dismiss: () -> Void
    @State private var selection: URL?
    @FocusState private var gridIsFocused: Bool
    @AppStorage private var layout: DesktopLayout

    init(store: DesktopStore, updateController: UpdateController, defaults: UserDefaults = .standard, dismiss: @escaping () -> Void) {
        self.store = store
        self.updateController = updateController
        self.dismiss = dismiss
        _layout = AppStorage(wrappedValue: .list, "desktopLayout", store: defaults)
    }

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
        .frame(width: 340)
        .background {
            Button("선택한 파일 열기") { openSelection() }
                .keyboardShortcut(.defaultAction)
                .hidden()
                .accessibilityHidden(true)
        }
        .onExitCommand { dismiss() }
        .onMoveCommand { direction in moveSelection(direction) }
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
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("바탕화면").font(.headline)
                Text(store.folderURL == nil ? "OneButton" : "\(store.items.count)개 항목")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        .help(store.folderURL?.path ?? "바탕화면 파일을 메뉴 막대에서 열어 보세요.")
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
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("바탕화면을 가까이").font(.headline)
                Text("폴더를 한 번 연결하면\n여기서 파일을 바로 열 수 있어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button("바탕화면 연결…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isChoosingFolder)
                    .accessibilityIdentifier("desktop.connect")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if store.items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.folderURL != nil ? "tray" : "folder.badge.questionmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(emptyMessage).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
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
                                                     count: DesktopLayout.gridColumnCount), spacing: 8) {
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
            }
            .frame(height: contentHeight)
        }
    }

    private var contentHeight: CGFloat {
        if layout == .list { return min(CGFloat(store.items.count) * 40 + 12, 330) }
        let rows = (store.items.count + DesktopLayout.gridColumnCount - 1) / DesktopLayout.gridColumnCount
        return min(CGFloat(rows) * 106 + 16, 330)
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
        return "바탕화면에 표시할 파일이 없어요."
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
            if store.hasConnection {
                Button("바탕화면 다시 연결…") { chooseFolder() }
                    .disabled(store.isChoosingFolder || store.openingURL != nil)
                    .accessibilityIdentifier("desktop.reconnect")
            }
            Spacer()
            Menu {
                Button("업데이트 확인…") {
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
                Label(updateController.availableUpdateVersion == nil ? "업데이트" : "업데이트 있음",
                      systemImage: updateController.availableUpdateVersion == nil
                        ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("desktop.updates")
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityIdentifier("desktop.quit")
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                                               itemCount: store.items.count) else { return }
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
