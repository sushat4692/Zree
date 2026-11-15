import SwiftUI
import NoteCore

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if app.selectedID == nil {
                EmptyState()
            } else {
                DetailView()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = app.errorMessage {
                ErrorBar(message: error)
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.vertical, 8)

            if !app.tagCloud.isEmpty {
                TagStrip()
                Divider()
            }

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
            HStack {
                Text(app.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    app.chooseVault()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Vaultを開く (⇧⌘O)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
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
            if !row.snippet.isEmpty {
                Text(row.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(Self.format(row.mtimeMs))
                if !row.tags.isEmpty {
                    Text("·")
                    Text(row.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .lineLimit(1)
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
            Text("Vaultを開いてください")
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
            if app.preview {
                HSplitView {
                    editor
                    PreviewView()
                        .frame(minWidth: 260)
                }
            } else {
                editor
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(text: Binding(
            get: { app.body },
            set: { newValue in
                app.body = newValue
                app.bodyDidChange()
            }
        ))
    }
}

struct Header: View {
    @Environment(AppState.self) private var app
    @FocusState private var titleFocused: Bool

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

            Spacer()

            if !app.selectedTags.isEmpty {
                Text(app.selectedTags.sorted().map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                app.preview.toggle()
            } label: {
                Image(systemName: app.preview ? "sidebar.right" : "rectangle.split.2x1")
            }
            .buttonStyle(.borderless)
            .help("プレビュー (⇧⌘P)")

            Button {
                app.trashSelected()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("ゴミ箱へ移動")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
