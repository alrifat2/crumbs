import AppKit
import SwiftUI

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
    @State private var launchError: String?

    var body: some View {
        let matches = LauncherSearch.matches(apps, query: query)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                LauncherSearchField(query: $query, move: { delta in
                    if actions.highlighted != nil { actions.move(delta) } else { move(delta, in: matches) }
                }, submit: {
                    if let action = actions.highlighted { perform(action) }
                    else if let selection { open(selection) }
                }, cancel: {
                    if actions.highlighted != nil { actions.highlighted = nil }
                    else if actions.showsInfo { actions.showsInfo = false }
                    else { dismiss(true) }
                })
                    .fixedSize(horizontal: false, vertical: true)
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
                applicationList(matches)
                    .frame(width: actions.showsInfo ? Theme.panelSize.width / 2 : Theme.panelSize.width)
                if actions.showsInfo, let app = matches.first(where: { $0.id == selection }) {
                    ApplicationInfoView(app: app) { actions.showsInfo = false }
                        .frame(width: Theme.panelSize.width / 2)
                        .overlay(alignment: .leading) { Divider() }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: Theme.panelSize.width, alignment: .leading)
            .clipped()
            .animation(reduceMotion ? nil : Theme.panelContentAnimation, value: actions.showsInfo)
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
                    if let selection {
                        let actionsVisible = actions.highlighted != nil
                        HStack(spacing: 0) {
                            footerButton("Open", action: { open(selection) }) {
                                footerKey(Image(systemName: "return"))
                            }
                            .foregroundStyle(ink.opacity(actionsVisible ? Theme.secondaryAlpha : Theme.primaryAlpha))
                            footerButton("Actions", action: { actions.highlighted = actions.highlighted == nil ? .open : nil }) {
                                HStack(spacing: 3) {
                                    footerKey(Image(systemName: "command"))
                                    footerKey(Text("K"))
                                }
                            }
                            .foregroundStyle(ink.opacity(actionsVisible ? Theme.primaryAlpha : Theme.secondaryAlpha))
                            .keyboardShortcut("k", modifiers: .command)
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
            let discovered = await LauncherApplication.discover()
            guard !Task.isCancelled else { return }
            apps = discovered
            loaded = true
            selection = LauncherSearch.matches(apps, query: query).first?.id
        }
        .onChange(of: query) {
            actions.highlighted = nil
            selection = matches.first?.id
            if selection == nil { actions.showsInfo = false }
            launchError = nil
        }
    }

    private func applicationList(_ matches: [LauncherApplication]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !actions.showsInfo {
                        Text("Applications").font(Theme.detailFont.bold()).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
                    ForEach(matches) { app in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .renderingMode(.original)
                                .resizable()
                                .frame(width: Theme.appIconSize, height: Theme.appIconSize)
                            Text(app.name).font(Theme.appNameFont).lineLimit(1)
                            Spacer()
                            if !actions.showsInfo {
                                Text("Application").font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            }
                        }
                        .padding(.horizontal, Theme.rowInset)
                        .frame(height: Theme.rowHeight)
                        .background(selection == app.id ? ink.opacity(Theme.selectionAlpha) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(app.url) }
                        .onTapGesture { selection = app.id }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selection == app.id ? [.isSelected, .isButton] : .isButton)
                        .accessibilityAction { open(app.url) }
                    }
                    if matches.isEmpty {
                        Text(loaded ? "No applications found" : "Loading applications…")
                            .font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha)).padding(10)
                    }
                }
                .padding(.horizontal, Theme.listInset)
            }
            .contentMargins(.top, Theme.surfaceSpacing, for: .scrollContent)
            .contentMargins(.bottom, Theme.footerHeight, for: .scrollContent)
            .scrollIndicators(.hidden)
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

    private func move(_ delta: Int, in matches: [LauncherApplication]) {
        if let index = matches.firstIndex(where: { $0.id == selection }) {
            selection = matches[max(0, min(matches.count - 1, index + delta))].id
        }
    }

    private func perform(_ action: ApplicationAction) {
        guard let selection else { return }
        actions.perform(action, on: selection, open: open, dismiss: { dismiss(false) })
    }

    private func open(_ url: URL) {
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
