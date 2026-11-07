import AppKit
import SwiftUI

@main
struct FullscreenFixture: App {
    var body: some Scene {
        WindowGroup("OneButton 전체 화면 검증") {
            FixtureView()
        }
    }
}

private struct FixtureView: View {
    @State private var isFullScreen = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "macwindow").font(.system(size: 64))
            Text(isFullScreen ? "전체 화면 테스트 중" : "OneButton 전체 화면 검증")
                .font(.largeTitle)
            Text("테스트 전용 창입니다. 사용자 문서를 열지 않습니다.")
                .foregroundStyle(.secondary)
            Button("전체 화면 전환") { NSApp.keyWindow?.toggleFullScreen(nil) }
                .accessibilityIdentifier("fixture.fullscreen")
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }
}
