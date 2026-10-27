// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// The user guide from docs/user-guide, bundled so it works offline and matches this version of the app.
/// The same Markdown files are what GitHub shows in the repository.
struct UserGuide {
    struct Page: Identifiable, Hashable { let file: String; let title: String; let section: String; var id: String { file } }
    let title: String
    let updated: String
    let sections: [(title: String, pages: [Page])]
    var pages: [Page] { sections.flatMap(\.pages) }
    let folder: URL

    static let shared: UserGuide? = {
        guard let folder = Bundle.main.url(forResource: "user-guide", withExtension: nil),
              let data = try? Data(contentsOf: folder.appendingPathComponent("guide.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["sections"] as? [[String: Any]] else { return nil }
        let parsed = sections.compactMap { section -> (String, [Page])? in
            guard let title = section["title"] as? String, let pages = section["pages"] as? [[String: String]] else { return nil }
            return (title, pages.compactMap { page in
                guard let file = page["file"], let name = page["title"] else { return nil }
                return Page(file: file, title: name, section: title)
            })
        }
        return UserGuide(title: root["title"] as? String ?? "User guide", updated: root["updated"] as? String ?? "",
                         sections: parsed.map { (title: $0.0, pages: $0.1) }, folder: folder)
    }()

    func text(of page: Page) -> String {
        (try? String(contentsOf: folder.appendingPathComponent(page.file), encoding: .utf8)) ?? ""
    }
    func image(_ path: String) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(path).path)
    }
}

/// Contents, with search across page titles and text, as in the RØDE and NewPipe guides.
struct UserGuideView: View {
    @State private var search = ""
    @State private var opened: String?
    private let guide = UserGuide.shared

    var body: some View {
        Group {
            if let guide {
                List {
                    if !Bundle.main.preferredLocalizations.contains(where: { $0.hasPrefix("en") }) {
                        Text("The guide is in English.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(guide.sections, id: \.title) { section in
                        let pages = section.pages.filter(matches)
                        if !pages.isEmpty {
                            Section(section.title) {
                                ForEach(pages) { page in
                                    NavigationLink(page.title, tag: page.file, selection: $opened) { UserGuidePageView(guide: guide, page: page) }
                                        .accessibilityIdentifier("guidePage-" + page.file)
                                }
                            }
                        }
                    }
                }
                .searchable(text: $search, prompt: Text("Search the guide"))
#if DEBUG || DRIFTLOOM_DEVICE_TESTING
                .task {
                    let arguments = ProcessInfo.processInfo.arguments
                    if let flag = arguments.firstIndex(of: "--guide-smoke"), arguments.indices.contains(flag + 1), arguments[flag + 1].hasSuffix(".md") {
                        try? await Task.sleep(nanoseconds: 800_000_000); opened = arguments[flag + 1]
                    }
                }
#endif
                .navigationTitle(guide.title)
            } else {
                Text("The user guide isn't available in this build.").foregroundStyle(.secondary).padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func matches(_ page: UserGuide.Page) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let guide else { return true }
        return page.title.localizedCaseInsensitiveContains(query) || guide.text(of: page).localizedCaseInsensitiveContains(query)
    }
}

/// One page, with Previous and Next; links to other pages open in place.
struct UserGuidePageView: View {
    let guide: UserGuide
    @State var page: UserGuide.Page

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.section.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).id("top")
                    ForEach(Array(GuideMarkdown.blocks(guide.text(of: page)).enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                    if !guide.updated.isEmpty {
                        Text("Last updated: \(guide.updated)").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    Divider().padding(.vertical, 4)
                    HStack(alignment: .top) {
                        if let previous = neighbour(-1) {
                            Button { page = previous } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Previous").font(.caption).foregroundStyle(.secondary)
                                    Text(previous.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                }
                            }.accessibilityIdentifier("guidePrevious")
                        }
                        Spacer(minLength: 16)
                        if let next = neighbour(1) {
                            Button { page = next } label: {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Next").font(.caption).foregroundStyle(.secondary)
                                    Text(next.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                                }
                            }.accessibilityIdentifier("guideNext")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
            }
            .onChange(of: page) { _ in proxy.scrollTo("top", anchor: .top) }
        }
        .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
        // Links between pages stay in the guide; web links open in the browser.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == nil, let target = guide.pages.first(where: { $0.file == url.lastPathComponent }) {
                page = target
                return .handled
            }
            return .systemAction
        })
    }

    private func neighbour(_ step: Int) -> UserGuide.Page? {
        guard let index = guide.pages.firstIndex(of: page), guide.pages.indices.contains(index + step) else { return nil }
        return guide.pages[index + step]
    }

    @ViewBuilder private func blockView(_ block: GuideMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(GuideMarkdown.inline(text)).font(level == 1 ? .title.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level == 1 ? 0 : 6).accessibilityAddTraits(.isHeader)
        case let .paragraph(text):
            Text(GuideMarkdown.inline(text)).fixedSize(horizontal: false, vertical: true)
        case let .list(items, numbered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(numbered ? "\(index + 1)." : "•").foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing)
                        Text(GuideMarkdown.inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .note(text):
            Text(GuideMarkdown.inline(text)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppStyle.accent.opacity(0.1)).cornerRadius(10)
        case let .image(alt, path):
            if let image = guide.image(path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 460)
                    .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                    .frame(maxWidth: .infinity).accessibilityLabel(alt)
            }
        }
    }
}

/// The small part of Markdown the guide uses: headings, paragraphs, lists, notes and images.
enum GuideMarkdown {
    enum Block { case heading(Int, String), paragraph(String), list([String], numbered: Bool), note(String), image(alt: String, path: String) }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = [], paragraph: [String] = [], items: [String] = [], numbered = false
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !items.isEmpty { blocks.append(.list(items, numbered: numbered)); items = [] }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let level = line.prefix(while: { $0 == "#" }).count as Int?, level > 0, level <= 3, line.dropFirst(level).hasPrefix(" ") {
                flush(); blocks.append(.heading(level, String(line.dropFirst(level + 1)))); continue
            }
            if line.hasPrefix("!["), let close = line.firstIndex(of: "]"), line[close...].hasPrefix("]("), line.hasSuffix(")") {
                flush()
                let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close])
                let path = String(line[line.index(close, offsetBy: 2)..<line.index(before: line.endIndex)])
                blocks.append(.image(alt: alt, path: path)); continue
            }
            if line.hasPrefix("> ") { flush(); blocks.append(.note(String(line.dropFirst(2)))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty || (numbered && !items.isEmpty) { flush() }
                numbered = false; items.append(String(line.dropFirst(2))); continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty, line[dot...].hasPrefix(". ") {
                if !paragraph.isEmpty || (!numbered && !items.isEmpty) { flush() }
                numbered = true; items.append(String(line[line.index(dot, offsetBy: 2)...])); continue
            }
            if !items.isEmpty { items[items.count - 1] += " " + line; continue }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
