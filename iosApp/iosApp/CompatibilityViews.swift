// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

/// Preserve native navigation on current systems and use the supported iOS 15 container.
struct AppNavigation<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(iOS 16, *) { NavigationStack(root: content) }
        else { NavigationView(content: content).navigationViewStyle(.stack) }
    }
}

struct BrowseLink<Content: View>: View {
    let route: BrowseRoute
    let onPlay: (BrowseItem) -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        NavigationLink(destination: AnyView(BrowsePageView(route: route, onPlay: onPlay)), label: content)
            .isDetailLink(false)
    }
}

struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }
    var body: some View {
        Button(action: action) { Label(title, systemImage: systemImage) }
    }
}

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text
    init(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) {
        self.title = title; self.systemImage = systemImage; self.message = Text(message)
    }
    /// A message that is already user-facing text, such as an error from the server.
    @_disfavoredOverload init<S: StringProtocol>(_ title: LocalizedStringKey, systemImage: String, message: S) {
        self.title = title; self.systemImage = systemImage; self.message = Text(message)
    }
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            message.foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    @ViewBuilder func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16, *) { scrollDismissesKeyboard(.interactively) }
        else { self }
    }
}
