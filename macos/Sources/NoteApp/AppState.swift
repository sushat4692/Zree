import AppKit
import Foundation
import Observation
import NoteCore

struct NoteRow: Identifiable, Hashable {
    let id: String
    let title: String
    let snippet: String
    let tags: [String]
    let mtimeMs: Int64
}

@MainActor
@Observable
final class AppState {
    nonisolated init() {}

    private(set) var session: NoteSession?
    private(set) var vaultPath: String?

    var query: String = ""
    var selectedTags: Set<String> = []
    private(set) var rows: [NoteRow] = []
    private(set) var tagCloud: [TagCount] = []

    private(set) var selectedID: String?
    var titleDraft: String = ""
    var body: String = ""
    var preview: Bool = false
    var status: String = ""
    var errorMessage: String?

    private var seenMtime: Int64 = 0
    private var isDirty = false
    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let vault = "vaultPath"
        static let lastNote = "lastNoteID"
    }

    // MARK: - Vault

    func restore() {
        guard session == nil else { return }
        if let path = defaults.string(forKey: Keys.vault), FileManager.default.fileExists(atPath: path) {
            openVault(path)
        }
    }

    @MainActor
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Vaultにする"
        panel.message = "Markdownノートのフォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            openVault(url.path)
        }
    }

    func openVault(_ path: String) {
        do {
            session = try NoteSession.open(root: path)
            vaultPath = path
            defaults.set(path, forKey: Keys.vault)
            selectedID = nil
            body = ""
            titleDraft = ""
            seenMtime = 0
            isDirty = false
            errorMessage = nil
            refreshAll()
            let last = defaults.string(forKey: Keys.lastNote)
            if let last, rows.contains(where: { $0.id == last }) {
                select(last)
            } else if let first = rows.first {
                select(first.id)
            }
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Listing

    func refreshAll() {
        reloadRows()
        reloadTags()
    }

    func reloadRows() {
        guard let session else {
            rows = []
            return
        }
        let hits = session.search(query: query, tags: Array(selectedTags), limit: 0)
        rows = hits.map {
            NoteRow(
                id: $0.id,
                title: $0.title,
                snippet: $0.snippet,
                tags: $0.tags,
                mtimeMs: $0.mtimeMs
            )
        }
        status = "\(rows.count) / \(session.search(query: "", tags: [], limit: 0).count) ノート"
    }

    func reloadTags() {
        tagCloud = session?.tags() ?? []
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
        reloadRows()
    }

    func setQuery(_ q: String) {
        query = q
        reloadRows()
    }

    // MARK: - Selection & loading

    func select(_ id: String?) {
        guard id != selectedID else { return }
        saveNow()
        selectedID = id
        loadSelected()
    }

    private func loadSelected() {
        guard let session, let id = selectedID else {
            titleDraft = ""
            body = ""
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            body = try session.read(id: id)
            if let row = rows.first(where: { $0.id == id }) {
                titleDraft = row.title
                seenMtime = row.mtimeMs
            } else {
                titleDraft = (id as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
                seenMtime = 0
            }
            isDirty = false
            defaults.set(id, forKey: Keys.lastNote)
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Saving

    func bodyDidChange() {
        guard !isLoading else { return }
        isDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard isDirty, let session, let id = selectedID else { return }
        do {
            let meta = try session.write(id: id, body: body, seenMtimeMs: seenMtime)
            seenMtime = meta.mtimeMs
            isDirty = false
            errorMessage = nil
            if let idx = rows.firstIndex(where: { $0.id == id }) {
                let row = rows[idx]
                rows[idx] = NoteRow(
                    id: row.id,
                    title: row.title,
                    snippet: row.snippet,
                    tags: row.tags,
                    mtimeMs: meta.mtimeMs
                )
            }
        } catch {
            errorMessage = "保存できません: \(describe(error))"
        }
    }

    // MARK: - Mutations

    func newNote() {
        saveNow()
        guard let session else { return }
        do {
            let meta = try session.create(title: nil, body: "")
            refreshAll()
            selectedID = meta.id
            titleDraft = meta.title
            body = ""
            seenMtime = meta.mtimeMs
            isDirty = false
            defaults.set(meta.id, forKey: Keys.lastNote)
        } catch {
            errorMessage = describe(error)
        }
    }

    func renameSelected() {
        guard let session, let id = selectedID else { return }
        let wanted = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = rows.first(where: { $0.id == id })?.title ?? ""
        guard !wanted.isEmpty, wanted != current else { return }
        saveNow()
        do {
            let meta = try session.rename(id: id, title: wanted)
            selectedID = meta.id
            titleDraft = meta.title
            seenMtime = meta.mtimeMs
            isDirty = false
            defaults.set(meta.id, forKey: Keys.lastNote)
            refreshAll()
        } catch {
            errorMessage = "リネームできません: \(describe(error))"
            titleDraft = current
        }
    }

    func trashSelected() {
        guard let session, let id = selectedID else { return }
        saveTask?.cancel()
        isDirty = false
        do {
            _ = try session.trash(id: id)
            selectedID = nil
            body = ""
            titleDraft = ""
            refreshAll()
            if let next = rows.first { select(next.id) }
        } catch {
            errorMessage = describe(error)
        }
    }

    func revealInFinder() {
        guard let vaultPath, let id = selectedID else { return }
        let url = URL(fileURLWithPath: vaultPath).appendingPathComponent(id)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reindex() {
        saveNow()
        do {
            try session?.reindex()
            refreshAll()
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Preview helpers

    func blocks(of text: String) -> [Block] {
        session?.blocksOf(text: text) ?? []
    }

    func attributed(_ text: String) -> AttributedString {
        guard let session else { return AttributedString(text) }
        var out = AttributedString()
        for piece in session.inline(text: text) {
            switch piece {
            case .text(let s):
                out.append(AttributedString(s))
            case .bold(let s):
                var a = AttributedString(s)
                a.inlinePresentationIntent = .stronglyEmphasized
                out.append(a)
            case .italic(let s):
                var a = AttributedString(s)
                a.inlinePresentationIntent = .emphasized
                out.append(a)
            case .strike(let s):
                var a = AttributedString(s)
                a.strikethroughStyle = .single
                out.append(a)
            case .code(let s):
                var a = AttributedString(s)
                a.font = .system(.body, design: .monospaced)
                out.append(a)
            case .link(let label, let url):
                var a = AttributedString(label)
                a.link = URL(string: url)
                out.append(a)
            case .image(let src, let alt):
                out.append(AttributedString(alt.isEmpty ? "[画像: \(src)]" : alt))
            }
        }
        return out
    }

    func imageURL(for src: String) -> URL? {
        guard let session, let id = selectedID else { return nil }
        guard let path = try? session.resolveAsset(id: id, src: src) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let d = localized.errorDescription {
            return d
        }
        return "\(error)"
    }
}
