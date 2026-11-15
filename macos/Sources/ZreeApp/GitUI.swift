import SwiftUI
import ZreeCore

struct GitFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            if let st = app.gitStatus {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(st.branch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if st.ahead > 0 {
                    Text("↑\(st.ahead)").font(.caption2).foregroundStyle(.secondary)
                }
                if st.behind > 0 {
                    Text("↓\(st.behind)").font(.caption2).foregroundStyle(.secondary)
                }
                if st.changed > 0 {
                    Text("●\(st.changed)").font(.caption2).foregroundStyle(.orange)
                }
                if !st.conflicts.isEmpty {
                    Text("⚠\(st.conflicts.count)").font(.caption2).foregroundStyle(.red)
                }
                if app.autoSyncEnabled {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("自動同期: \(app.autoSyncMinutes)分ごと")
                }
                Button {
                    app.sync()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .opacity(app.gitBusy ? 0.4 : 1)
                }
                .buttonStyle(.borderless)
                .disabled(app.gitBusy)
                .help("commit → pull → push (⇧⌘U)")
            } else {
                Button("Git未設定") { app.showSettings = true }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }

            Spacer()

            Text(app.status)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Button {
                app.chooseVault()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Vaultを開く (⇧⌘O)")

            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct ConflictBanner: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("衝突 \(app.conflicts.count) 件 — どちらの内容を残しますか")
                    .font(.caption)
                    .bold()
                Spacer()
                if app.conflicts.isEmpty {
                    Button("マージ確定") { app.finishMerge() }
                        .buttonStyle(.borderless)
                }
            }
            ForEach(app.conflicts, id: \.self) { path in
                HStack(spacing: 6) {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("自分") { app.resolveConflict(path, .mine) }
                    Button("相手") { app.resolveConflict(path, .theirs) }
                    Button("両方") { app.resolveConflict(path, .both) }
                }
                .font(.caption)
            }
            if app.conflicts.isEmpty {
                Text("すべて解決済みです。「マージ確定」でコミットしてpushします。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }
}

struct GitSettingsSheet: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("表示")
                .font(.headline)

            DisplaySettingsBlock(
                title: "エディタ",
                family: $app.editorFontFamily,
                size: $app.editorFontSize,
                lineHeight: $app.editorLineHeight,
                families: app.availableFontFamilies
            )

            DisplaySettingsBlock(
                title: "プレビュー",
                family: $app.previewFontFamily,
                size: $app.previewFontSize,
                lineHeight: $app.previewLineHeight,
                families: app.availableFontFamilies
            )

            Divider()

            Text("Git同期")
                .font(.headline)

            if let st = app.gitStatus {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ブランチ: \(st.branch)")
                    Text("追跡: \(st.upstream)")
                    Text("状態: ↑\(st.ahead) ↓\(st.behind) 変更\(st.changed)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("このVaultはGitリポジトリではありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("自動同期（commit → pull → push）", isOn: $app.autoSyncEnabled)
                    .toggleStyle(.switch)
                HStack(spacing: 8) {
                    Text("間隔").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $app.autoSyncMinutes) {
                        Text("1分").tag(1)
                        Text("5分").tag(5)
                        Text("10分").tag(10)
                        Text("15分").tag(15)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .disabled(!app.autoSyncEnabled)
                    if let last = app.lastSyncAt {
                        Text("最終: \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("変更があるときだけコミットします。衝突を検出したら停止して確認を求めます。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("リモートURL").font(.caption).foregroundStyle(.secondary)
                TextField("git@github.com:you/vault.git", text: $app.remoteDraft)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Personal Access Token（HTTPSの場合）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("ghp_…", text: $app.tokenDraft)
                    .textFieldStyle(.roundedBorder)
                Text("キーチェーンに保存します")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                if app.gitStatus == nil {
                    Button("Gitリポジトリを初期化") { app.initGit() }
                }
                Spacer()
                Button("閉じる") { app.showSettings = false }
                Button("保存") { app.applyGitSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 620)
        }
        .onDisappear { app.saveDisplaySettings() }
    }
}

/// Font family / size / line height for one pane.
private struct DisplaySettingsBlock: View {
    let title: String
    @Binding var family: String?
    @Binding var size: Double
    @Binding var lineHeight: Double
    let families: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("フォント").font(.caption).frame(width: 56, alignment: .leading)
                Picker("", selection: $family) {
                    Text("システム").tag(nil as String?)
                    Divider()
                    ForEach(families, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            HStack(spacing: 8) {
                Text("サイズ").font(.caption).frame(width: 56, alignment: .leading)
                Stepper(value: $size, in: 10...32, step: 1) {
                    Text("\(Int(size)) pt").monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Text("行間").font(.caption).frame(width: 56, alignment: .leading)
                Slider(value: $lineHeight, in: 1.0...2.2, step: 0.05)
                Text(String(format: "%.2f", lineHeight)).monospacedDigit().font(.caption)
            }
        }
    }
}
