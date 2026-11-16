import AppKit
import SwiftUI
import ZreeCore

@main
struct ZreeMain: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("Zree", id: "main") {
            ContentView()
                .environment(app)
                .frame(minWidth: 860, minHeight: 560)
                .task { app.restore() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    app.flushAndSyncBlocking()
                }
        }
        // no title bar text: the content runs to the top of the window, with the traffic
        // lights floating over the sidebar
        .windowStyle(.hiddenTitleBar)
        .commands {
            ZreeCommands(app: app)
        }
    }
}

/// Menu commands. `openWindow` is only available from a `Commands` type, which is why this
/// is not inline in the `App`.
struct ZreeCommands: Commands {
    let app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        Group {
            // `replacing` rather than `after`: the default New Window also claims ⌘N, so
            // Zree would have two menu items on the same shortcut.
            CommandGroup(replacing: .newItem) {
                Button("新規ノート") { app.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("新規ウィンドウ") { openWindow(id: "main") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("ツリーを開く…") { app.chooseVault() }
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
            CommandMenu("書式") {
                Button("太字") { EditorCommands.toggleInline("**") }
                    .keyboardShortcut("b", modifiers: .command)
                Divider()
                Button("箇条書き") { EditorCommands.block(.bullet) }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("番号付きリスト") { EditorCommands.block(.ordered) }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Button("チェックボックス") { EditorCommands.block(.task) }
                    .keyboardShortcut("9", modifiers: [.command, .shift])
                Button("チェックを切り替え") { EditorCommands.toggleTask() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("見出し") { EditorCommands.block(.heading) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("引用") { EditorCommands.block(.quote) }
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                Divider()
                Button("インデント") { EditorCommands.indent(outdent: false) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("インデントを戻す") { EditorCommands.indent(outdent: true) }
                    .keyboardShortcut("[", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Finderで表示") { app.revealInFinder() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
