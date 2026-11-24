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
    @State private var launchError: String?

    var body: some View {
        let matches = LauncherSearch.matches(apps, query: query)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                LauncherSearchField(query: $query, move: { move($0, in: matches) },
                                    submit: { if let selection { open(selection) } },
                                    cancel: { dismiss(true) })
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("Applications").font(Theme.detailFont.bold()).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                        ForEach(matches) { app in
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .renderingMode(.original)
                                    .resizable()
                                    .frame(width: Theme.appIconSize, height: Theme.appIconSize)
                                Text(app.name).font(Theme.appNameFont).lineLimit(1)
                                Spacer()
                                Text("Application").font(Theme.detailFont).foregroundStyle(ink.opacity(Theme.secondaryAlpha))
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
            .overlay(alignment: .bottom) {
                HStack {
                    Button {
                        openSettings()
                        dismiss(false)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 30, height: 30)
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
                        Button { open(selection) } label: {
                            HStack(spacing: 8) {
                                Text("Open")
                                footerSymbol("return")
                            }
                            .font(Theme.actionFont)
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open")
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
        .onChange(of: query) { selection = matches.first?.id; launchError = nil }
    }

    private var surfaceBackground: some View {
        ZStack {
            Backdrop()
            (scheme == .dark ? Color.black : Color.white)
                .opacity(reduceTransparency ? 1 : Theme.scrimAlpha)
        }
    }

    private func footerSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(Theme.detailFont)
            .foregroundStyle(ink.opacity(Theme.secondaryAlpha))
            .frame(width: 21, height: 21)
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(ink.opacity(Theme.outlineAlpha)) }
            .accessibilityHidden(true)
    }

    private func move(_ delta: Int, in matches: [LauncherApplication]) {
        if let index = matches.firstIndex(where: { $0.id == selection }) {
            selection = matches[max(0, min(matches.count - 1, index + delta))].id
        }
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
