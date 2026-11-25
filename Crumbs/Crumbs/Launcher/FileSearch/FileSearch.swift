import Darwin
import FileSearchCore
import Foundation
import Synchronization

nonisolated enum FileSearch {
    // MDQuery needs a thread with a run loop. Keep it off Swift's cooperative executor.
    private static let worker = DispatchQueue(label: "Crumbs.FileSearch", qos: .userInitiated)

    private final class Request: Sendable {
        let cancelled = Mutex(false)
    }

    // The Rust function invokes both callbacks synchronously on the worker.
    private final class Collector {
        let request: Request
        var rows: [LauncherResult] = []

        init(_ request: Request) { self.request = request }
    }

    static func isMediaLibrary(_ url: URL) -> Bool { crumbs_inside_media_library(url.path) }

    static func stopIndexing() { crumbs_stop_file_index() }

    static var revision: UInt64 { crumbs_index_revision() }
    static var ready: Bool { crumbs_index_ready() }

    private static let index: Void = {
        let cache = URL.cachesDirectory.appending(path: "com.alrifat.Crumbs/filename-index-v3.json")
        crumbs_start_file_index(cache.path)
    }()

    // Finder ships Recents as a saved search. Read its predicate and scope from the installed system.
    private static let recents: (predicate: String, scope: String) = {
        struct SavedSearch: Decodable {
            struct Criteria: Decodable { let SearchScopes: [String] }
            let RawQuery: String
            let RawQueryDict: Criteria
        }
        let file = URL(filePath: "/System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch/Resources/search.savedSearch")
        if let data = try? Data(contentsOf: file),
           let search = try? PropertyListDecoder().decode(SavedSearch.self, from: data),
           let scope = search.RawQueryDict.SearchScopes.first {
            return (search.RawQuery, scope)
        }
        return (#"(kMDItemLastUsedDate = "*") && ((kMDItemContentTypeTree = "public.content") || (kMDItemContentTypeTree = "public.archive") || (kMDItemContentTypeTree = "com.microsoft.*"cdw))"#, "kMDQueryScopeMyFiles")
    }()

    struct Results: Sendable {
        let rows: [LauncherResult]
        let deniedFolders: [String]
    }

    // Open directory handles on the search worker so macOS can ask for consent.
    private static func requestRecentFolderAccess(_ request: Request) -> [String] {
        let locations = [URL.documentsDirectory, .downloadsDirectory, .desktopDirectory]

        var denied: [String] = []
        for location in locations {
            if request.cancelled.withLock({ $0 }) { break }
            let error = location.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return EINVAL }
                guard let directory = opendir(path) else { return errno }
                closedir(directory)
                return 0
            }
            if error == EACCES || error == EPERM {
                denied.append(location.lastPathComponent)
            }
        }
        return denied
    }

    static func matches(_ term: String, in directory: URL?) async throws -> Results {
        if !term.isEmpty { try await Task.sleep(for: .milliseconds(90)) }
        let request = Request()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                worker.async {
                    guard !request.cancelled.withLock({ $0 }) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let recentsRequested = term.isEmpty && directory == nil
                    let deniedFolders = recentsRequested ? requestRecentFolderAccess(request) : []
                    let collector = Collector(request)
                    let success = withExtendedLifetime(collector) {
                        let context = Unmanaged.passUnretained(collector).toOpaque()
                        let cancelled: @convention(c) (UnsafeMutableRawPointer?) -> Bool = { pointer in
                            Unmanaged<Collector>.fromOpaque(pointer!).takeUnretainedValue().request.cancelled.withLock { $0 }
                        }
                        let append: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Bool) -> Void = { pointer, path, folder in
                            let output = Unmanaged<Collector>.fromOpaque(pointer!).takeUnretainedValue()
                            let url = URL(filePath: String(cString: path!), directoryHint: folder ? .isDirectory : .notDirectory)
                            output.rows.append(LauncherResult(url: url, name: url.lastPathComponent,
                                                              kind: folder ? .folder : .file))
                        }
                        if recentsRequested {
                            return crumbs_recent_files(recents.predicate, recents.scope, context, cancelled, append)
                        }
                        _ = index
                        return crumbs_search_files(term, directory?.path, context, cancelled, append)
                    }
                    if request.cancelled.withLock({ $0 }) {
                        continuation.resume(throwing: CancellationError())
                    } else if success {
                        continuation.resume(returning: Results(rows: collector.rows, deniedFolders: deniedFolders))
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
            }
        } onCancel: {
            request.cancelled.withLock { $0 = true }
        }
    }
}
