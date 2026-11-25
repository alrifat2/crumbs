import AppKit
import CoreServices
import Quartz
import SwiftUI

private struct FilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Void) { view.close() }
}

private nonisolated struct ItemDetails: Sendable {
    struct Section: Identifiable {
        let title: String
        var rows: [Row]
        var id: String { title }
    }

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let sections: [Section]

    @concurrent
    static func folderSize(_ url: URL) async throws -> String {
        var pending = [url]
        var bytes: Int64 = 0
        var partial = false
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .totalFileSizeKey]
        while let folder = pending.popLast() {
            try Task.checkCancellation()
            let children: [URL]
            do { children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: []) }
            catch { partial = true; continue }
            for child in children {
                try Task.checkCancellation()
                if FileSearch.isMediaLibrary(child) { partial = true; continue }
                guard let values = try? child.resourceValues(forKeys: keys) else { partial = true; continue }
                if values.isSymbolicLink == true { continue }
                if values.isVolume == true { partial = true; continue }
                if values.isDirectory == true { pending.append(child) }
                else if let size = values.totalFileSize { bytes += Int64(size) }
                else { partial = true }
            }
        }
        return "\(bytes.formatted()) bytes" + (partial ? " (partial)" : "")
    }

    @concurrent
    static func load(_ result: LauncherResult) async throws -> Self {
        let url = result.url
        let keys: Set<URLResourceKey> = [.localizedTypeDescriptionKey, .totalFileSizeKey, .totalFileAllocatedSizeKey,
                                         .directoryEntryCountKey, .creationDateKey, .contentModificationDateKey,
                                         .addedToDirectoryDateKey, .tagNamesKey, .isUserImmutableKey, .isSystemImmutableKey,
                                         .hasHiddenExtensionKey]
        let values = try url.resourceValues(forKeys: keys)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let item = MDItemCreateWithURL(nil, url as CFURL)
        func metadata(_ key: CFString) -> Any? { item.flatMap { MDItemCopyAttribute($0, key) } }
        func section(_ title: String, _ fields: [(String, String?)]) -> Section {
            Section(title: title, rows: fields.compactMap { label, value in
                guard let value, !value.isEmpty else { return nil }
                return Row(label: label, value: value)
            })
        }

        var general: [(String, String?)] = [("Kind", values.localizedTypeDescription ?? result.kind.rawValue),
                                             ("Where", url.deletingLastPathComponent().path)]
        if result.kind == .folder {
            general.append(("Contents", values.directoryEntryCount.map { "\($0) items" }))
        } else if result.kind == .file {
            let size = values.totalFileSize ?? (attributes[.size] as? NSNumber)?.intValue
            general.append(("Size", size.map { "\($0.formatted()) bytes" }))
            general.append(("On disk", values.totalFileAllocatedSize.map { Int64($0).formatted(.byteCount(style: .file)) }))
        }
        general += [("Created", (values.creationDate ?? attributes[.creationDate] as? Date)?.formatted()), ("Modified", (values.contentModificationDate ?? attributes[.modificationDate] as? Date)?.formatted()),
                    ("Added", values.addedToDirectoryDate?.formatted()),
                    ("Last opened", (metadata(kMDItemLastUsedDate) as? Date)?.formatted()),
                    ("Locked", values.isUserImmutable == true || values.isSystemImmutable == true ? "Yes" : "No"),
                    ("Stationery pad", (metadata(kMDItemFSIsStationery) as? NSNumber).map { $0.boolValue ? "Yes" : "No" })]

        let more: [(String, String?)] = [
            ("Title", metadata(kMDItemTitle) as? String), ("Authors", (metadata(kMDItemAuthors) as? [String])?.joined(separator: ", ")),
            ("Pages", (metadata(kMDItemNumberOfPages) as? NSNumber)?.stringValue),
            ("Dimensions", (metadata(kMDItemPixelWidth) as? NSNumber).flatMap { width in
                (metadata(kMDItemPixelHeight) as? NSNumber).map { "\(width) × \($0)" }
            }),
            ("Duration", (metadata(kMDItemDurationSeconds) as? NSNumber).map { Duration.seconds($0.doubleValue).formatted() }),
            ("Where from", (metadata(kMDItemWhereFroms) as? [String])?.joined(separator: "\n"))
        ]
        var bundleFields: [(String, String?)] = []
        if result.kind == .application, let bundle = Bundle(url: url) {
            func value(_ key: String) -> String? { bundle.object(forInfoDictionaryKey: key) as? String }
            bundleFields = [("Version", value("CFBundleShortVersionString")), ("Build", value("CFBundleVersion")),
                            ("Identifier", bundle.bundleIdentifier), ("Executable", value("CFBundleExecutable")),
                            ("Minimum macOS", value("LSMinimumSystemVersion")), ("Copyright", value("NSHumanReadableCopyright"))]
        }
        var permissions: [(String, String?)] = []
        if let mode = attributes[.posixPermissions] as? NSNumber {
            func access(_ shift: Int) -> String {
                let bits = (mode.intValue >> shift) & 7
                let names = [(4, "Read"), (2, "Write"), (1, result.kind == .folder ? "Traverse" : "Execute")]
                return bits == 0 ? "No access" : names.compactMap { bits & $0.0 != 0 ? $0.1 : nil }.joined(separator: ", ")
            }
            permissions = [("Owner", (attributes[.ownerAccountName] as? String).map { "\($0) · \(access(6))" }),
                           ("Group", (attributes[.groupOwnerAccountName] as? String).map { "\($0) · \(access(3))" }),
                           ("Everyone", access(0))]
        }
        if let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            if let entryText = acl_to_text(acl, nil) {
                defer { acl_free(entryText) }
                let entries = String(cString: entryText).split(separator: "\n").dropFirst().joined(separator: "\n")
                permissions.append(("Access rules", entries))
            }
        }
        return Self(sections: [
            section("General", general), section("Application", bundleFields), section("More Info", more),
            section("Name & Extension", [("Name", url.lastPathComponent), ("Hide extension", values.hasHiddenExtension.map { $0 ? "Yes" : "No" })]),
            section("Tags", [("Tags", values.tagNames?.joined(separator: ", "))]),
            section("Comments", [("Comment", metadata(kMDItemFinderComment) as? String)]),
            section("Sharing & Permissions", permissions)
        ].filter { !$0.rows.isEmpty })
    }
}

struct ItemInfoView: View {
    let result: LauncherResult
    let close: () -> Void
    @State private var calculateSize = false
    @State private var folderSize: String?
    @State private var details: ItemDetails?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close info").help("Close info (Esc)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if result.kind == .application || result.kind == .folder {
                        Image(nsImage: result.kind == .application ? NSWorkspace.shared.icon(forFile: result.url.path) : NSWorkspace.shared.icon(for: .folder)).resizable().scaledToFit()
                            .frame(height: 72).frame(maxWidth: .infinity).accessibilityHidden(true)
                    } else {
                        FilePreview(url: result.url).frame(height: 132).accessibilityLabel("Preview")
                    }
                    if let error { Text(error).foregroundStyle(.secondary) }
                    if let details {
                        ForEach(details.sections) { section in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title).font(.subheadline.bold())
                                Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 4) {
                                    if result.kind != .file && section.title == "General" {
                                        GridRow {
                                            Text("Size").foregroundStyle(.secondary)
                                            if let folderSize { Text(folderSize) }
                                            else if calculateSize || result.kind == .application { Text("Calculating…") }
                                            else {
                                                Button("Calculate size") { calculateSize = true }
                                                    .buttonStyle(.link)
                                            }
                                        }
                                    }
                                    ForEach(section.rows) { row in
                                        GridRow {
                                            Text(row.label).foregroundStyle(.secondary)
                                            Text(row.value).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .font(.caption)
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .padding(.bottom, Theme.footerHeight - 12)
        .task(id: calculateSize) {
            guard calculateSize || result.kind == .application else { return }
            folderSize = try? await ItemDetails.folderSize(result.url)
        }
        .task {
            do {
                let loaded = try await ItemDetails.load(result)
                if !Task.isCancelled { details = loaded }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
