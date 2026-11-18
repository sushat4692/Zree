import SwiftUI
import ZreeEditor
import ZreeCore

struct ContentView: View {
    @Environment(AppState.self) private var app
    /// Height of the (invisible) title bar, measured at runtime, removed with negative padding.
    @State private var topInset: CGFloat = 0

    var body: some View {
        // A plain HSplitView, not NavigationSplitView: the latter reserves the title bar
        // area for its own toolbar, which left an empty strip at the top of the window.
        HSplitView {
            SidebarView()
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)

            Group {
                if app.selectedID == nil {
                    if app.vaultPath == nil {
                        FirstRunView()
                    } else {
                        EmptyState()
                    }
                } else {
                    DetailView()
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, -topInset)
        .overlay(alignment: .bottom) {
            if let error = app.errorMessage {
                ErrorBar(message: error)
            }
        }
        .overlay(alignment: .top) {
            if !app.conflicts.isEmpty || (app.gitStatus?.merging ?? false) {
                ConflictBanner()
            }
        }
        .sheet(isPresented: Bindable(app).showSettings) {
            GitSettingsSheet()
        }
        .sheet(isPresented: Bindable(app).showClone) {
            CloneSheet()
        }
        .tint(ZreePalette.accent)
        .background(WindowChrome(topInset: $topInset))
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // room for the window buttons: the title bar is hidden
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索（日本語OK）", text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, newValue in
                        app.setQuery(newValue)
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if !app.tagCloud.isEmpty {
                TagStrip()
                Divider()
            }

            HStack(spacing: 6) {
                Text(app.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("更新が新しい順") { app.sortOrder = .updatedDesc }
                    Button("更新が古い順") { app.sortOrder = .updatedAsc }
                    Button("作成が新しい順") { app.sortOrder = .createdDesc }
                    Button("作成が古い順") { app.sortOrder = .createdAsc }
                    Button("タイトル順 A→Z") { app.sortOrder = .titleAsc }
                    Button("タイトル順 Z→A") { app.sortOrder = .titleDesc }
                } label: {
                    Text("⇅ \(app.sortOrderLabel)")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            List(selection: Binding(
                get: { app.selectedID },
                set: { app.select($0) }
            )) {
                ForEach(app.rows) { row in
                    RowView(row: row)
                        .tag(row.id)
                }
            }
            .listStyle(.sidebar)
        }
        .safeAreaInset(edge: .bottom) {
            GitFooter()
        }
    }
}

struct TagStrip: View {
    @Environment(AppState.self) private var app
    @State private var expanded = false

    private var shown: [TagCount] {
        expanded ? app.tagCloud : Array(app.tagCloud.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(shown, id: \.tag) { tag in
                        let on = app.selectedTags.contains(tag.tag)
                        Button {
                            app.toggleTag(tag.tag)
                        } label: {
                            Text("#\(tag.tag) \(tag.count)")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(on ? Color.accentColor : Color.secondary.opacity(0.12))
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            Button(expanded ? "タグを畳む" : "すべてのタグ (\(app.tagCloud.count))") {
                expanded.toggle()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 6)
    }
}

struct RowView: View {
    let row: NoteRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text("更新 \(Self.format(row.mtimeMs))")
                if row.createdMs > 0 {
                    Text("· 作成 \(Self.format(row.createdMs))")
                }
                if !row.tags.isEmpty {
                    Text("·")
                    Text(row.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .lineLimit(1)
                        .foregroundStyle(ZreePalette.accent)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    static func format(_ ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm"
        return fmt.string(from: date)
    }
}

struct EmptyState: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("ツリーを開いてください")
                .font(.title3)
            Button("フォルダを選択…") { app.chooseVault() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBar: View {
    let message: String
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).lineLimit(2)
            Spacer()
            Button("閉じる") { app.errorMessage = nil }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.9))
        .foregroundStyle(.white)
    }
}

struct DetailView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Divider()
            EditorToolbar()
            Divider()
            editor
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: Binding(
            get: { app.body },
                set: { newValue in
                    app.body = newValue
                    app.bodyDidChange()
                }
            ),
            font: app.editorFont,
            lineHeight: app.lineHeight
        )
    }
}

struct Header: View {
    @Environment(AppState.self) private var app
    @FocusState private var titleFocused: Bool
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("タイトル", text: Binding(
                get: { app.titleDraft },
                set: { app.titleDraft = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .focused($titleFocused)
            .onSubmit { app.renameSelected() }
            .onChange(of: titleFocused) { _, focused in
                // commit the rename when the field loses focus (no explicit button)
                if !focused { app.renameSelected() }
            }

            Spacer()

            let dates = app.openNoteDates
            if dates.updated > 0 {
                Text("更新 \(RowView.format(dates.updated))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if dates.created > 0 {
                    Text("作成 \(RowView.format(dates.created))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !app.selectedTags.isEmpty {
                Text(app.selectedTags.sorted().map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("ゴミ箱へ移動")
            .confirmationDialog(
                "「\(app.titleDraft)」をゴミ箱へ移動しますか？",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("ゴミ箱へ移動", role: .destructive) { app.trashSelected() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("元に戻すには .trash フォルダから取り出してください。")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Same actions as the Android accessory bar.
struct EditorToolbar: View {
    @Environment(AppState.self) private var app

    private struct Action: Identifiable {
        let id = UUID()
        let label: String
        let help: String
        let run: () -> Void
    }

    private var actions: [Action] {
        [
            Action(label: "⇤", help: "インデントを戻す (⇧Tab)") { EditorCommands.indent(outdent: true) },
            Action(label: "⇥", help: "インデント (Tab)") { EditorCommands.indent(outdent: false) },
            Action(label: "•", help: "箇条書き") { EditorCommands.block(.bullet) },
            Action(label: "1.", help: "番号付き") { EditorCommands.block(.ordered) },
            Action(label: "☐", help: "チェックボックス") { EditorCommands.block(.task) },
            Action(label: "☑", help: "チェックを切り替え") { EditorCommands.toggleTask() },
            Action(label: "#", help: "見出し") { EditorCommands.block(.heading) },
            Action(label: "❝", help: "引用") { EditorCommands.block(.quote) },
            Action(label: "B", help: "太字") { EditorCommands.toggleInline("**") },
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(actions) { action in
                    Button(action.label) { action.run() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minWidth: 26, minHeight: 22)
                        .help(action.help)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .background(.bar)
    }
}


/// Hides the traffic lights and makes the window draggable by its background.
///
/// With `.hiddenTitleBar` there is no title bar left, so without this the buttons float
/// over the sidebar and the window cannot be moved at all.
struct WindowChrome: NSViewRepresentable {
    @Binding var topInset: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // no title bar text, no traffic lights
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }

            // SwiftUI keeps the title bar height as a safe-area inset; report it so the
            // content can slide up by exactly that much. The window stays a normal titled
            // window, so materials and the rounded corners render correctly.
            DispatchQueue.main.async {
                topInset = window.contentView?.safeAreaInsets.top ?? 0
            }

            if let path = ProcessInfo.processInfo.environment["ZREE_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    guard let content = window.contentView,
                          let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
                    content.cacheDisplay(in: content.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: path))
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
