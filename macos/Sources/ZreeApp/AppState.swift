import SwiftUI
import AppKit
import Foundation
import Observation
import ZreeCore

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

    private(set) var session: ZreeSession?
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

    // Git
    private(set) var git: GitRepo?
    private(set) var gitStatus: GitStatus?
    var conflicts: [String] = []
    var gitBusy = false
    var showSettings = false
    var remoteDraft = ""
    var tokenDraft = ""

    // Auto-sync
    var autoSyncEnabled: Bool = true {
        didSet { autoSyncPrefsChanged() }
    }
    var autoSyncMinutes: Int = 5 {
        didSet { autoSyncPrefsChanged() }
    }
    private var restoringPrefs = false
    var lastSyncAt: Date?
    private var autoSyncTask: Task<Void, Never>?
    private var autoSyncFailures = 0

    // Clone flow
    var showClone = false
    var cloneURL = ""
    var cloneToken = ""
    var cloneParent = ""
    var cloneMessage: String?
    var cloning = false

    // Display settings (editor and preview are configured separately)
    var editorFontFamily: String?
    var editorFontSize: Double = 14
    var editorLineHeight: Double = 1.4
    var previewFontFamily: String?
    var previewFontSize: Double = 15
    var previewLineHeight: Double = 1.6

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let vault = "vaultPath"
        static let lastNote = "lastNoteID"
        static let token = "gitToken"
        static let username = "gitUsername"
        static let autoSyncOn = "autoSyncEnabled"
        static let autoSyncMinutes = "autoSyncMinutes"
        static let editorFontFamily = "editorFontFamily"
        static let editorFontSize = "editorFontSize"
        static let editorLineHeight = "editorLineHeight"
        static let previewFontFamily = "previewFontFamily"
        static let previewFontSize = "previewFontSize"
        static let previewLineHeight = "previewLineHeight"
    }

    // MARK: - Vault

    func restore() {
        guard session == nil else { return }
        // auto-sync preferences; suppress the setters' writes so they cannot
        // clobber a value we have not read yet
        restoringPrefs = true
        if defaults.object(forKey: Keys.autoSyncOn) != nil {
            autoSyncEnabled = defaults.bool(forKey: Keys.autoSyncOn)
        }
        let savedMinutes = defaults.integer(forKey: Keys.autoSyncMinutes)
        if savedMinutes > 0 {
            autoSyncMinutes = savedMinutes
        }
        restoringPrefs = false

        if defaults.object(forKey: Keys.editorFontSize) != nil {
            editorFontFamily = defaults.string(forKey: Keys.editorFontFamily)
            editorFontSize = defaults.double(forKey: Keys.editorFontSize)
            editorLineHeight = defaults.double(forKey: Keys.editorLineHeight)
            previewFontFamily = defaults.string(forKey: Keys.previewFontFamily)
            previewFontSize = defaults.double(forKey: Keys.previewFontSize)
            previewLineHeight = defaults.double(forKey: Keys.previewLineHeight)
        }
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
            session = try ZreeSession.open(root: path)
            vaultPath = path
            defaults.set(path, forKey: Keys.vault)
            selectedID = nil
            body = ""
            titleDraft = ""
            seenMtime = 0
            isDirty = false
            errorMessage = nil
            setupGit()
            refreshAll()
            let last = defaults.string(forKey: Keys.lastNote)
            if let last, rows.contains(where: { $0.id == last }) {
                select(last)
            } else if let first = rows.first {
                select(first.id)
            }
            autoPullOnOpen()
            restartAutoSync()
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

    // MARK: - Git

    func setupGit() {
        guard let vaultPath else {
            git = nil
            gitStatus = nil
            return
        }
        let token = Keychain.migrateFromDefaults(defaults, defaultsKey: Keys.token, account: Keys.token)
        if isGitRepo(root: vaultPath) {
            git = try? GitRepo.open(
                root: vaultPath,
                username: defaults.string(forKey: Keys.username),
                token: token
            )
        } else {
            git = nil
        }
        remoteDraft = git?.remoteUrl() ?? ""
        tokenDraft = Keychain.get(Keys.token) ?? ""
        refreshGitStatus()
    }

    /// Pull on launch, but only when it cannot surprise the user:
    /// clean working tree, nothing staged, no conflicts, and actually behind.
    func autoPullOnOpen() {
        guard let repo = git, let st = gitStatus else { return }
        guard st.changed == 0, st.behind > 0, st.conflicts.isEmpty, !st.merging else { return }

        status = "同期中…"
        Task.detached { [weak self] in
            let result = Result { try repo.pull() }
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let outcome):
                    if case let .conflicts(paths) = outcome {
                        self.conflicts = paths
                    }
                    self.refreshAll()
                    self.refreshGitStatus()
                    self.reloadSelectedIfClean()
                case .failure(let error):
                    self.errorMessage = self.describe(error)
                }
            }
        }
    }

    func reloadSelectedIfClean() {
        guard !isDirty, selectedID != nil else { return }
        loadSelected()
    }

    func refreshGitStatus() {
        gitStatus = try? git?.status()
        if let status = gitStatus, !status.conflicts.isEmpty {
            conflicts = status.conflicts
        }
    }

    // MARK: - Clone

    /// `parent/<repo name>` derived from the URL, following git's own convention.
    var cloneTargetPath: String? {
        guard !cloneParent.isEmpty else { return nil }
        let name = Self.repoName(from: cloneURL)
        guard !name.isEmpty else { return nil }
        return (cloneParent as NSString).appendingPathComponent(name)
    }

    var canClone: Bool {
        // not URL(string:) — scp-style remotes (git@host:owner/repo) fail that parse
        guard !cloning, cloneTargetPath != nil else { return false }
        let trimmed = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("/") || trimmed.contains(":")
    }

    static func repoName(from url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == ":" })
        return parts.last.map(String.init) ?? ""
    }

    @MainActor
    func chooseCloneParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "ここに保存"
        panel.message = "クローン先の親フォルダを選択（リポジトリ名のフォルダを新規作成します）"
        if panel.runModal() == .OK, let url = panel.url {
            cloneParent = url.path
            cloneMessage = nil
        }
    }

    func performClone() {
        guard let target = cloneTargetPath else { return }
        let url = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = cloneToken.trimmingCharacters(in: .whitespaces)
        let parentOK = cloneParent.isEmpty == false

        if parentOK, FileManager.default.fileExists(atPath: target) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: target)) ?? []
            if !contents.filter({ $0 != ".DS_Store" }).isEmpty {
                cloneMessage = "保存先に既にファイルがあります: \(target)"
                return
            }
        }

        cloning = true
        cloneMessage = "接続しています…"

        Task.detached { [url, target, token] in
            let result: Result<Void, Error> = Result {
                _ = try GitRepo.clone(
                    url: url,
                    path: target,
                    username: nil,
                    token: token.isEmpty ? nil : token
                )
            }
            await MainActor.run {
                self.cloning = false
                switch result {
                case .success:
                    if !token.isEmpty {
                        Keychain.set(token, for: Keys.token)
                        self.defaults.removeObject(forKey: Keys.token)
                    }
                    self.cloneMessage = "✓ クローン完了"
                    self.showClone = false
                    self.openVault(target)
                case .failure(let error):
                    self.cloneMessage = self.describe(error)
                }
            }
        }
    }

    func initGit() {
        guard let vaultPath else { return }
        do {
            git = try GitRepo.ensure(root: vaultPath)
            if !remoteDraft.isEmpty {
                try git?.setRemote(url: remoteDraft)
            }
            setupGit()
        } catch {
            errorMessage = describe(error)
        }
    }

    func applyGitSettings() {
        guard let git else { return }
        do {
            if !remoteDraft.isEmpty {
                try git.setRemote(url: remoteDraft)
            }
            let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            git.setAuth(username: nil, token: token.isEmpty ? nil : token)
            if token.isEmpty {
                Keychain.delete(Keys.token)
            } else {
                Keychain.set(token, for: Keys.token)
            }
            refreshGitStatus()
            showSettings = false
        } catch {
            errorMessage = describe(error)
        }
    }

    func sync() {
        Task { await runSync(auto: false) }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    /// commit → pull → push, off the main thread.
    private func runSync(auto: Bool) async {
        guard let repo = git else { return }
        saveNow()
        gitBusy = true
        let message = auto ? "zree: autosync \(Self.stamp())" : "zree: sync from macOS"
        let result: Result<SyncReport, Error> = await Task.detached {
            Result { try repo.sync(message: message) }
        }.value
        gitBusy = false

        switch result {
        case .success(let report):
            autoSyncFailures = 0
            conflicts = report.conflicts
            lastSyncAt = Date()
            refreshAll()
            refreshGitStatus()
            reloadSelectedIfClean()
        case .failure(let error):
            // a failing remote (missing PAT, offline) should not spam on every tick
            autoSyncFailures += 1
            if auto && autoSyncFailures >= 3 {
                autoSyncEnabled = false
                errorMessage = "自動同期を停止しました（3回連続で失敗）: \(describe(error))"
            } else {
                errorMessage = describe(error)
            }
        }
    }

    // MARK: - Auto sync

    private func autoSyncPrefsChanged() {
        if !restoringPrefs {
            defaults.set(autoSyncEnabled, forKey: Keys.autoSyncOn)
            defaults.set(autoSyncMinutes, forKey: Keys.autoSyncMinutes)
        }
        restartAutoSync()
    }

    func restartAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        autoSyncFailures = 0
        guard autoSyncEnabled, git != nil else { return }

        let seconds = UInt64(max(1, autoSyncMinutes)) * 60 * 1_000_000_000
        autoSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: seconds)
                if Task.isCancelled { break }
                guard let self else { break }
                guard !self.gitBusy else { continue }
                if let st = self.gitStatus, st.merging || !st.conflicts.isEmpty {
                    continue  // let the human resolve first
                }
                await self.runSync(auto: true)
            }
        }
    }

    /// Final save + sync when the app is quitting.
    func flushAndSyncBlocking() {
        saveNow()
        autoSyncTask?.cancel()
        guard let repo = git else { return }
        // re-read the worktree: autosave may have just written files
        refreshGitStatus()
        if let st = gitStatus, st.merging || !st.conflicts.isEmpty { return }
        _ = try? repo.sync(message: "zree: autosync \(Self.stamp()) (quit)")
        refreshGitStatus()
    }

    func pullOnly() {
        guard let git else { return }
        saveNow()
        gitBusy = true
        defer { gitBusy = false }
        do {
            let outcome = try git.pull()
            if case let .conflicts(paths) = outcome {
                conflicts = paths
            }
            refreshAll()
            refreshGitStatus()
        } catch {
            errorMessage = describe(error)
        }
    }

    func resolveConflict(_ path: String, _ choice: ConflictChoice) {
        guard let git else { return }
        do {
            try git.resolve(path: path, choice: choice)
            conflicts = (try? git.conflicts()) ?? []
            refreshAll()
        } catch {
            errorMessage = describe(error)
        }
    }

    func finishMerge() {
        guard let git else { return }
        do {
            try git.commitMerge(message: "zree: resolve conflicts")
            conflicts = []
            try git.push()
            refreshAll()
            refreshGitStatus()
        } catch {
            errorMessage = describe(error)
        }
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

    // MARK: - Display settings

    func saveDisplaySettings() {
        defaults.set(editorFontFamily, forKey: Keys.editorFontFamily)
        defaults.set(editorFontSize, forKey: Keys.editorFontSize)
        defaults.set(editorLineHeight, forKey: Keys.editorLineHeight)
        defaults.set(previewFontFamily, forKey: Keys.previewFontFamily)
        defaults.set(previewFontSize, forKey: Keys.previewFontSize)
        defaults.set(previewLineHeight, forKey: Keys.previewLineHeight)
    }

    /// Font families installed on this Mac, plus nil for the system font.
    var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var editorFont: NSFont {
        if let family = editorFontFamily, let font = NSFont(name: family, size: editorFontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    var editorParagraphStyle: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = max(0.8, editorLineHeight)
        return style
    }

    var previewFont: Font {
        if let family = previewFontFamily {
            return .custom(family, size: previewFontSize)
        }
        return .system(size: previewFontSize)
    }

    var previewLineSpacing: CGFloat {
        max(0, previewFontSize * (previewLineHeight - 1))
    }

    // MARK: - Editor assists

    func listAction(_ line: String) -> ListAction {
        ZreeCore.listAction(line: line)
    }

    func indentLine(_ line: String, outdent: Bool) -> String? {
        ZreeCore.indentLine(line: line, outdent: outdent)
    }

    func completionContext(_ beforeCursor: String) -> CompletionContext? {
        ZreeCore.completionContext(beforeCursor: beforeCursor)
    }

    func suggestTags(_ prefix: String, limit: UInt32 = 8) -> [String] {
        session?.suggestTags(prefix: prefix, limit: limit) ?? []
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
                a.link = noteLink(for: url) ?? URL(string: url)
                out.append(a)
            case .image(let src, let alt):
                out.append(AttributedString(alt.isEmpty ? "[画像: \(src)]" : alt))
            }
        }
        return out
    }

    /// In-app link to another note, using a `zree://note?id=` URL so the
    /// preview can intercept it instead of handing it to the browser.
    func noteLink(for href: String) -> URL? {
        guard let session, let id = selectedID else { return nil }
        guard let target = session.resolveLink(id: id, href: href) else { return nil }
        var components = URLComponents()
        components.scheme = "zree"
        components.host = "note"
        components.queryItems = [URLQueryItem(name: "id", value: target)]
        return components.url
    }

    /// Returns true when the URL pointed at a note in this vault.
    @discardableResult
    func openNoteLink(_ url: URL) -> Bool {
        guard url.scheme == "zree",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name == "id" })?.value
        else { return false }
        select(target)
        return true
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
