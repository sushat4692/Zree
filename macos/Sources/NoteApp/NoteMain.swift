import SwiftUI
import NoteCore

@main
struct NoteMain: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("Note") {
            ContentView()
                .environment(app)
                .frame(minWidth: 860, minHeight: 560)
                .task { app.restore() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新規ノート") { app.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Vaultを開く…") { app.chooseVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
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
