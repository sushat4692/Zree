import AppKit
import SwiftUI

struct CloneSheet: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
                Text("Gitからクローン")
                    .font(.headline)
            }

            Text("リポジトリを複製して、このMacのVaultとして開きます。既存のノートは上書きされません（新規フォルダに取得します）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("リモートURL").font(.caption).foregroundStyle(.secondary)
                TextField("https://github.com/you/vault.git", text: $app.cloneURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Personal Access Token（HTTPS・プライベートリポジトリの場合）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("ghp_…", text: $app.cloneToken)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("保存先").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(app.cloneParent.isEmpty ? "未選択" : app.cloneParent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(app.cloneParent.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("選択…") { app.chooseCloneParent() }
                }
                if let target = app.cloneTargetPath {
                    Text("→ \(target)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let message = app.cloneMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("✓") ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if app.cloning {
                    ProgressView()
                        .controlSize(.small)
                    Text("クローン中…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("キャンセル") { app.showClone = false }
                    .disabled(app.cloning)
                Button("クローンして開く") { app.performClone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!app.canClone)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct FirstRunView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Zreeへようこそ")
                .font(.title2).bold()
            Text("ノートはプレーンなMarkdownファイルです。Gitリポジトリを複製するか、既存のフォルダを開いてください。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Gitからクローン…") { app.showClone = true }
                    .keyboardShortcut(.defaultAction)
                Button("フォルダを開く…") { app.chooseVault() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
