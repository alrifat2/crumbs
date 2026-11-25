import AppKit
import QuickLook
import SwiftUI

enum ApplicationAction: String, CaseIterable {
    case open = "Open"
    case reveal = "Show in Finder"
    case info = "Get Info"
    case preview = "Quick Look"
    case share = "Share…"
}

private struct ApplicationActionsMenu: View {
    @Binding var highlighted: ApplicationAction
    let perform: (ApplicationAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ApplicationAction.allCases, id: \.self) { action in
                Button {
                    perform(action)
                } label: {
                    Text(action.rawValue)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .foregroundStyle(highlighted == action ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
                        .background(highlighted == action ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = action } }
            }
        }
        .padding(5)
        .frame(width: 132)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.16)) }
        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
    }
}

@Observable
final class ApplicationActions {
    var highlighted: ApplicationAction?
    var showsInfo = false
    var previewURL: URL?

    func move(_ delta: Int) {
        let actions = ApplicationAction.allCases
        guard let highlighted, let index = actions.firstIndex(of: highlighted) else { return }
        self.highlighted = actions[max(0, min(actions.count - 1, index + delta))]
    }

    func perform(_ action: ApplicationAction, on url: URL, open: (URL) -> Void, dismiss: () -> Void) {
        highlighted = nil
        switch action {
        case .open: open(url)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
        case .info: showsInfo = true
        case .preview: previewURL = url
        case .share:
            guard let view = NSApp.keyWindow?.contentView else { return }
            let rect = NSRect(x: view.bounds.maxX - 40, y: view.isFlipped ? view.bounds.maxY - Theme.footerHeight : Theme.footerHeight,
                              width: 1, height: 1)
            NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: view, preferredEdge: .minX)
        }
    }
}

struct ApplicationActionsPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var actions: ApplicationActions
    let perform: (ApplicationAction) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    if actions.highlighted != nil {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { actions.highlighted = nil }
                            .accessibilityHidden(true)
                            .transition(.identity)
                        ApplicationActionsMenu(highlighted: Binding(
                            get: { actions.highlighted ?? .open },
                            set: { if actions.highlighted != nil { actions.highlighted = $0 } }
                        ), perform: perform)
                        .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
                        .padding(.trailing, Theme.listInset)
                        .padding(.bottom, Theme.footerHeight)
                    }
                }
                .allowsHitTesting(actions.highlighted != nil)
                .animation(reduceMotion ? nil : Theme.panelContentAnimation, value: actions.highlighted != nil)
            }
            .quickLookPreview($actions.previewURL)
    }
}
