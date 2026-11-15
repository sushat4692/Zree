import AppKit
import SwiftUI
import ZreeCore

@main
struct ZreeMain: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("Zree") {
            ContentView()
                .environment(app)
                .frame(minWidth: 860, minHeight: 560)
                .task { app.restore() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.flushAndSyncBlocking()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新規ノート") { app.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Vaultを開く…") { app.chooseVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Gitからクローン…") { app.showClone = true }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("同期 (commit → pull → push)") { app.sync() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("設定") { app.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("保存") { app.saveNow() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("再インデックス") { app.reindex() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("プレビュー切り替え") { app.preview.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Finderで表示") { app.revealInFinder() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
