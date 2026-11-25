# Launcher search

The empty launcher lists installed apps. Typing filters their names and adds matching localized System Settings panes. Return or a double-click opens the selected result. Application actions are available for application rows.

Crumbs walks the local, system, user, and Cryptex Applications folders, plus CoreServices/Applications and Finder.app. Recursion covers Utilities. Resolving symlinks before deduplication keeps overlapping paths from producing multiple rows for the same bundle.

System Settings discovery reads the installed ExtensionKit extensions for the Settings UI extension point and opens a pane by bundle identifier. Searches match pane names. For individual controls, open the pane and use System Settings’ own search.

## Files

Typing `@` lists available search scopes. Keep typing to filter by prefix, then press Return on the highlighted scope or click it. Completing a scope token also activates it immediately.

Typing `@file` switches the focused search field to a folder symbol and the Files prompt. Pasting `@file budget` starts the same search for “budget”. Backspace in an empty File field leaves the scope.

Selecting a folder displays “Search in” and its name with a Tab key hint. Tab enters that folder. The field shows the parent and current folder above the query, with the full path available on hover. The list shows its indexed direct children, and typing filters their names. Tab can enter another selected folder. Go back (⌘[) in the footer returns to the previous folder or search, including when the current query has no matches. Backspace with an empty query also returns to the previous folder or search. Return opens the selection in macOS.

With a file or folder selected, **Show Info** (⌘K) opens a read-only side panel. It follows the selection. Escape, ⌘K, or the close button closes it. Files use an embedded Quick Look preview. Folder info includes a folder icon, an item count when available, and an optional size calculation. Sizes exclude symbolic links. Inaccessible subfolders, media libraries, and nested volumes produce a partial total. The panel displays available Finder and Spotlight metadata, ownership, and access rules.

An empty File field at the top level runs Finder’s installed Recents saved search through Spotlight. Crumbs reads its predicate and scope, sorts by last-used date, and excludes image and audio results and media libraries. If the saved-search file is unavailable, Crumbs uses the recent-document predicate and My Files scope. The heading shows the total number of loaded files. Scroll or use the arrow keys to reach rows below the panel. Opening Recents works before the filename index starts. Spotlight silently omits protected folders when Crumbs lacks access. On entering Recents the app opens directory handles for Documents, Downloads, and Desktop so macOS can request access before gathering results. Denied folders are named in the launcher. To restore access, update Privacy & Security in System Settings and reopen Recents.

Filename search also excludes files whose registered filename type is an image or audio type. The index and Recents skip user Music and Pictures folders, media library packages, and Apple media database directories. File and folder rows use icons for their type so displaying a result does not open its path.

The first typed filename starts a process-owned Rust worker. Four background walkers enumerate accessible files and folders on the Mac and publish batches as they finish. The launcher searches names in memory with `nucleo-matcher`, ranks exact names first, and displays up to 100 fuzzy matches. Results refresh as the index changes. Clearing the query returns to Recents. Crumbs stores no file-opening history.

The `ignore` walker respects ignore files and skips dotfiles, symbolic links, app bundles, Photos and Music libraries, caches, DerivedData, node_modules, network volumes mounted under /Volumes, and system internals such as /private and /System/Volumes. macOS permissions determine which protected folders the worker can read. To include a denied Desktop, Documents, or Downloads folder, grant Crumbs access in System Settings and relaunch it.

The worker subscribes to FSEvents with `notify` before crawling and reconciles changed paths in batches. It writes a private, atomically replaced snapshot of paths and file/folder flags in `~/Library/Caches/com.alrifat.Crumbs/filename-index-v3.json`. On restart the snapshot serves searches during reconciliation of offline changes. Dropped events trigger a fresh walk. Deleting the cache while Crumbs is closed forces a cold index on the next filename search.

Xcode builds the Rust library for each selected Mac architecture. With rustup, install the corresponding standard libraries before a universal build (`rustup target add aarch64-apple-darwin x86_64-apple-darwin`). For SwiftPM, run the following from the repository root after checkout and after Rust changes:

```sh
Crumbs/Crumbs/Launcher/FileSearch/Rust/build.sh
swift test
cargo test --locked --manifest-path Crumbs/Crumbs/Launcher/FileSearch/Rust/Cargo.toml --target-dir .build/rust-tests -- --include-ignored
```

In the running app, type `@file`, navigate Recents with the arrow keys, then type and clear a filename. Return opens the selection. Backspace in an empty File field leaves the scope.
