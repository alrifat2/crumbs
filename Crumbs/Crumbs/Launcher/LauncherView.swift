import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct FadeDistances: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

struct LauncherView: View {
    let hotKeyAvailable: Bool
    let dismiss: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var topFade: CGFloat = 0
    @State private var bottomFade: CGFloat = 0

    private var ink: Color { scheme == .dark ? .white : .black }

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchPresented = false
    @State private var resultsPresented = false
    @State private var apps: [LauncherApplication] = []
    @State private var query = ""
    @State private var selection: URL?
    @State private var loaded = false
    @State private var actions = ApplicationActions()
    @State private var showsFileInfo = false
    private var showsInfo: Bool { actions.showsInfo || showsFileInfo }
    @State private var launchError: String?

    @State private var activeScope: LauncherScope?
    private struct FileRequest: Equatable {
        let directory: URL?
        let term: String
        var isRecents: Bool { directory == nil && term.isEmpty }
    }

    @State private var directory: URL?
    @State private var folderHistory: [FileRequest] = []
    @State private var highlightedScope: LauncherScope?
    private var fileScope: Bool { activeScope == .file }
    private var scopeSuggestions: [LauncherScope]? {
        activeScope == nil ? LauncherScope.suggestions(for: query) : nil
    }
    @State private var panes: [LauncherResult] = []
    @State private var files: [LauncherResult] = []
    @State private var searching = false

    private var matches: [LauncherResult] {
        if fileScope { return files }
        if scopeSuggestions != nil { return [] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let applications = LauncherSearch.matches(apps, query: term).map {
            LauncherResult(url: $0.url, name: $0.name, kind: .application)
        }
        return applications + (term.isEmpty ? [] : panes.filter { $0.name.localizedStandardContains(term) })
    }

    private func edit(_ text: String) {
        let previousRequest = fileRequest
        if activeScope == nil, let activation = LauncherScope.activation(for: text) {
            activeScope = activation.scope
            query = activation.query
        } else {
            query = text
        }
        if fileRequest != previousRequest || !fileScope { files = [] }
        highlightedScope = scopeSuggestions?.first
        actions.highlighted = nil
        launchError = nil
        selection = matches.first?.id
        if matches.first?.application == nil { actions.showsInfo = false }
    }

    private var emptyMessage: String {
        if scopeSuggestions != nil { return "No matching scopes" }
        if !fileScope { return loaded ? "No matches" : "Loading applications…" }
        if directory != nil {
            if searching { return "Loading folder…" }
            return query.isEmpty ? "No searchable items in this folder" : "No matches in this folder"
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return searching ? "Loading recent files…" : "No recent files" }
        if searching { return FileSearch.ready ? "Searching…" : "Indexing filenames…" }
        return "No matching files or folders"
    }

    var body: some View {
        let matches = self.matches
        let selected = matches.first { $0.id == selection }
        let selectedApp = selected?.application
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: fileScope && directory == nil ? "folder" : "magnifyingglass")
                    .foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                VStack(alignment: .leading, spacing: 0) {
                    if let directory {
                        let parent = directory.deletingLastPathComponent().lastPathComponent
                        HStack(spacing: 5) {
                            if !parent.isEmpty && parent != "/" {
                                Text(parent)
                                    .foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(directory.lastPathComponent)
                                .fontWeight(.semibold)
                                .layoutPriority(1)
                        }
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Searching in \(directory.path)")
                        .help(directory.path)
                    }
                    LauncherSearchField(query: Binding(get: { query }, set: edit), fileScope: fileScope, enterFolder: {
                        guard let result = files.first(where: { $0.id == selection && $0.kind == .folder }),
                              let request = fileRequest else { return false }
                        folderHistory.append(request)
                        changeDirectory(to: result.url, query: "")
                        return true
                    }, leaveScope: {
                        if !folderHistory.isEmpty {
                            goBack()
                        } else {
                            activeScope = nil
                            edit("")
                        }
                    }, move: { delta in
                        if let scopes = scopeSuggestions {
                            if let highlightedScope, let index = scopes.firstIndex(of: highlightedScope) {
                                self.highlightedScope = scopes[max(0, min(scopes.count - 1, index + delta))]
                            }
                        } else if actions.highlighted != nil { actions.move(delta) }
                        else { move(delta, in: matches) }
                    }, submit: {
                        if let highlightedScope { edit(highlightedScope.rawValue) }
                        else if let action = actions.highlighted { perform(action) }
                        else if let selection { open(selection) }
                    }, cancel: {
                        if actions.highlighted != nil { actions.highlighted = nil }
                        else if showsFileInfo { showsFileInfo = false }
                        else if actions.showsInfo { actions.showsInfo = false }
                        else { dismiss(true) }
                    })
                        .fixedSize(horizontal: false, vertical: true)
                        .background(alignment: .leading) {
                            if query.isEmpty {
                                Text(directory != nil ? "Filter by name" : activeScope?.title ?? "Search apps and commands...")
                                    .foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                                    .padding(.leading, 2)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .font(.system(size: Theme.searchFontSize))
            .padding(.horizontal, 20)
            .frame(height: Theme.headerHeight)
            .background { surfaceBackground }
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
            .scaleEffect(searchPresented || reduceMotion ? 1 : 0.96)
            Color.clear
                .frame(height: Theme.surfaceSpacing)
                .contentShape(Rectangle())
                .onTapGesture { dismiss(true) }
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                resultList(matches)
                    .frame(width: showsInfo ? Theme.panelSize.width / 2 : Theme.panelSize.width)
                if showsInfo, let selected {
                    ItemInfoView(result: selected) {
                        actions.showsInfo = false
                        showsFileInfo = false
                    }
                        .id(selected.id)
                        .frame(width: Theme.panelSize.width / 2)
                        .overlay(alignment: .leading) { Divider() }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: Theme.panelSize.width, alignment: .leading)
            .clipped()
            .animation(reduceMotion ? nil : Theme.panelContentAnimation, value: showsInfo)
            .overlay(alignment: .bottom) {
                HStack {
                    Button {
                        openSettings()
                        dismiss(false)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                    .help("Open Crumbs Settings")

                    if let launchError {
                        Text(launchError).font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                    } else if !hotKeyAvailable {
                        Text("Shortcut unavailable (⌃⇧Space). Open Crumbs from Finder.")
                            .font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                    }
                    Spacer()
                    if selection != nil || !folderHistory.isEmpty {
                        let actionsVisible = actions.highlighted != nil
                        HStack(spacing: 0) {
                            if !folderHistory.isEmpty {
                                footerButton("Go back", action: goBack) {
                                    HStack(spacing: 3) {
                                        footerKey(Image(systemName: "command"))
                                        footerKey(Text("["))
                                    }
                                }
                                .keyboardShortcut("[", modifiers: .command)
                            }
                            if let selection {
                                footerButton("Open", action: { open(selection) }) {
                                    footerKey(Image(systemName: "return"))
                                }
                                .foregroundStyle(ink.opacity(actionsVisible ? Theme.secondaryAlpha : Theme.primaryAlpha))
                                if selectedApp != nil || (fileScope && selected != nil) {
                                    footerButton(fileScope ? "Show Info" : "Actions", action: {
                                        if fileScope { showsFileInfo.toggle() }
                                        else { actions.highlighted = actions.highlighted == nil ? .open : nil }
                                    }) {
                                        HStack(spacing: 3) {
                                            footerKey(Image(systemName: "command"))
                                            footerKey(Text("K"))
                                        }
                                    }
                                    .foregroundStyle(ink.opacity(actionsVisible || showsFileInfo ? Theme.primaryAlpha : Theme.secondaryAlpha))
                                    .keyboardShortcut("k", modifiers: .command)
                                }
                            }
                        }
                        .glassEffect(.regular, in: Capsule())
                    }
                }
                .padding(.horizontal, Theme.listInset)
                .frame(height: Theme.footerHeight)
            }
            .background { surfaceBackground }
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
            .scaleEffect(x: 1, y: resultsPresented || reduceMotion ? 1 : 0.94, anchor: .top)
            .offset(y: resultsPresented || reduceMotion ? 0 : -16)
            .opacity(resultsPresented || reduceMotion ? 1 : 0)
        }
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .foregroundStyle(ink.opacity(Theme.primaryAlpha))
        .modifier(ApplicationActionsPresentation(actions: actions, perform: perform))
        .onAppear {
            guard !reduceMotion else {
                searchPresented = true
                resultsPresented = true
                return
            }
            withAnimation(.spring(duration: 0.36, bounce: 0.28)) { searchPresented = true }
            withAnimation(.spring(duration: 0.42, bounce: 0.22).delay(0.10)) { resultsPresented = true }
        }
        .task {
            async let settings = SettingsCatalog.discover()
            async let applications = LauncherApplication.discover()
            let catalog = await (applications, settings)
            guard !Task.isCancelled else { return }
            apps = catalog.0
            panes = catalog.1
            loaded = true
            if !fileScope { selection = self.matches.first?.id }
        }
        .task(id: fileRequest) {
            let request = fileRequest
            guard let request else { searching = false; return }
            searching = true
            defer { if fileRequest == request { searching = false } }
            do {
                var revision: UInt64?
                repeat {
                    let current = FileSearch.revision
                    if current != revision {
                        let result = try await FileSearch.matches(request.term, in: request.directory)
                        guard !Task.isCancelled, fileRequest == request else { return }
                        let found = result.rows
                        if !result.deniedFolders.isEmpty {
                            launchError = "Access denied to " + result.deniedFolders.joined(separator: ", ") + "."
                        }
                        files = found
                        if !found.contains(where: { $0.id == selection }) { selection = found.first?.id }
                        searching = !request.isRecents && !FileSearch.ready
                        revision = current
                    }
                    if request.isRecents { break }
                    try await Task.sleep(for: .milliseconds(450))
                } while !Task.isCancelled
            } catch {
                if !Task.isCancelled, fileRequest == request { launchError = error.localizedDescription }
            }
        }
        .onChange(of: selection) {
            if !fileScope || selection == nil { showsFileInfo = false }
            if selectedApp == nil {
                actions.highlighted = nil
                actions.showsInfo = false
            }
        }
    }

    private func goBack() {
        guard let previous = folderHistory.popLast() else { return }
        changeDirectory(to: previous.directory, query: previous.term)
    }

    private func changeDirectory(to folder: URL?, query text: String) {
        directory = folder
        files = []
        edit(text)
    }

    private var fileRequest: FileRequest? {
        fileScope ? FileRequest(directory: directory, term: query.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    private func icon(for result: LauncherResult) -> Image {
        switch result.kind {
        case .settings: Image(systemName: "gearshape")
        case .application: Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
        case .folder: Image(nsImage: NSWorkspace.shared.icon(for: .folder))
        case .file: Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: result.url.pathExtension) ?? .data))
        }
    }

    private var sectionTitle: String {
        if scopeSuggestions != nil { return "Search scopes" }
        if directory != nil { return query.isEmpty ? "Contents" : "Matches" }
        if fileRequest?.isRecents == true {
            return files.isEmpty ? "Recents" : "Recents (\(files.count))"
        }
        if fileScope { return "Files" }
        return query.isEmpty ? "Applications" : "Results"
    }

    private func resultList(_ matches: [LauncherResult]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !showsInfo {
                        Text(sectionTitle).font(Theme.detailFont.bold()).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
                    if let scopes = scopeSuggestions {
                        ForEach(scopes, id: \.self) { scope in
                            Button { edit(scope.rawValue) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: scope.symbol)
                                        .frame(width: Theme.appIconSize)
                                    Text(scope.rawValue).font(Theme.appNameFont)
                                    Spacer()
                                    Text(scope.title).font(Theme.detailFont).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, Theme.rowInset)
                                .frame(height: Theme.rowHeight)
                                .background(highlightedScope == scope ? ink.opacity(Theme.selectionAlpha) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(highlightedScope == scope ? .isSelected : [])
                        }
                    }
                    ForEach(matches) { result in
                        HStack(spacing: 12) {
                            icon(for: result)
                                .renderingMode(.original)
                                .resizable()
                                .frame(width: Theme.appIconSize, height: Theme.appIconSize)
                            Text(result.name).font(Theme.appNameFont).lineLimit(1)
                            Spacer()
                            if !showsInfo && result.kind == .folder && selection == result.id {
                                HStack(spacing: 6) {
                                    Text("Search in \(result.name)").lineLimit(1)
                                    Text("tab").padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(ink.opacity(Theme.selectionAlpha), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            } else if !showsInfo {
                                Text(fileScope ? (result.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath : result.kind.rawValue)
                                    .lineLimit(1).truncationMode(.head).font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            }
                        }
                        .padding(.horizontal, Theme.rowInset)
                        .frame(height: Theme.rowHeight)
                        .background(selection == result.id ? ink.opacity(Theme.selectionAlpha) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(result.url) }
                        .onTapGesture { selection = result.id }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selection == result.id ? [.isSelected, .isButton] : .isButton)
                        .accessibilityAction { open(result.url) }
                    }
                    if matches.isEmpty && scopeSuggestions?.isEmpty != false {
                        Text(emptyMessage)
                            .font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha)).padding(10)
                    }
                }
                .padding(.horizontal, Theme.listInset)
            }
            .contentMargins(.top, Theme.surfaceSpacing, for: .scrollContent)
            .contentMargins(.bottom, Theme.footerHeight, for: .scrollContent)
            .scrollIndicators(fileRequest?.isRecents == true ? .visible : .hidden, axes: .vertical)
            .onScrollGeometryChange(for: FadeDistances.self) { geometry in
                FadeDistances(
                    top: min(Theme.rowHeight / 2, max(0, geometry.contentOffset.y + geometry.contentInsets.top)),
                    bottom: min(Theme.footerHeight, max(0, geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.containerSize.height - geometry.contentOffset.y))
                )
            } action: { _, distances in
                topFade = distances.top
                bottomFade = distances.bottom
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: topFade)
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: bottomFade)
                }
            }
            .onChange(of: highlightedScope) { _, scope in if let scope { proxy.scrollTo(scope) } }
            .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private var surfaceBackground: some View {
        ZStack {
            Backdrop()
            (scheme == .dark ? Color.black : Color.white)
                .opacity(reduceTransparency ? 1 : Theme.scrimAlpha)
        }
    }

    private func footerButton(_ title: LocalizedStringKey, action: @escaping () -> Void,
                              @ViewBuilder keys: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                keys()
            }
            .font(Theme.actionFont)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footerKey(_ symbol: some View) -> some View {
        symbol
            .font(.system(size: 10))
            .foregroundStyle(ink.opacity(Theme.secondaryAlpha))
            .frame(width: 16, height: 16)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(Theme.outlineAlpha)) }
            .accessibilityHidden(true)
    }

    private func move(_ delta: Int, in matches: [LauncherResult]) {
        if let index = matches.firstIndex(where: { $0.id == selection }) {
            selection = matches[max(0, min(matches.count - 1, index + delta))].id
        }
    }

    private func perform(_ action: ApplicationAction) {
        guard let selection, matches.contains(where: { $0.id == selection && $0.kind == .application }) else { return }
        actions.perform(action, on: selection, open: open, dismiss: { dismiss(false) })
    }

    private func open(_ url: URL) {
        guard let result = matches.first(where: { $0.id == url }) else { return }
        if result.kind != .application {
            if NSWorkspace.shared.open(url) { dismiss(false) }
            else { launchError = "Couldn’t open " + result.name }
            return
        }
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
                dismiss(false)
            } catch {
                launchError = error.localizedDescription
            }
        }
    }
}
