import AppKit
import SwiftUI

private nonisolated struct ApplicationInfo: Sendable {
    let version: String?
    let build: String?
    let identifier: String?
    let created: Date?
    let modified: Date?

    @concurrent
    static func load(_ url: URL) async -> Self {
        let bundle = Bundle(url: url)
        let dates = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return Self(version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    build: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                    identifier: bundle?.bundleIdentifier,
                    created: dates?.creationDate, modified: dates?.contentModificationDate)
    }

    @concurrent
    static func bundleSize(_ url: URL) async -> Int64? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        var complete = true
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                         errorHandler: { _, _ in complete = false; return false }) else { return nil }
        var bytes: Int64 = 0
        while let file = files.nextObject() as? URL {
            guard !Task.isCancelled, let values = try? file.resourceValues(forKeys: keys) else { return nil }
            if values.isRegularFile == true {
                guard let size = values.fileSize else { return nil }
                bytes += Int64(size)
            }
        }
        return complete ? bytes : nil
    }
}

struct ApplicationInfoView: View {
    let app: LauncherApplication
    let close: () -> Void
    @State private var info: ApplicationInfo?
    @State private var size: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(app.name).font(.headline).lineLimit(2)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close application info")
                    .help("Close application info (Esc)")
            }
            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                    row("Kind", "Application")
                    if let version = info?.version { row("Version", version) }
                    if let build = info?.build { row("Build", build) }
                    if let size { row("Size", size.formatted(.byteCount(style: .file))) }
                    row("Where", app.url.path)
                    if let date = info?.created { row("Created", date.formatted()) }
                    if let date = info?.modified { row("Modified", date.formatted()) }
                    if let identifier = info?.identifier { row("Identifier", identifier) }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .padding(16)
        .padding(.bottom, Theme.footerHeight - 16)
        .task(id: app.id) {
            info = nil
            size = nil
            let metadata = await ApplicationInfo.load(app.url)
            guard !Task.isCancelled else { return }
            info = metadata
            let bytes = await ApplicationInfo.bundleSize(app.url)
            guard !Task.isCancelled else { return }
            size = bytes
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
}
