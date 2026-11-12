// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomActivity
import UIKit
import UniformTypeIdentifiers

/// Saves a link to the PAL App Group inbox. Free-account sideloads offer an explicit copy action.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let action = UIButton(type: .system)
    private let done = UIButton(type: .system)
    private var handled = false
    private var link: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = String(localized: "Preparing link…")
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center; label.numberOfLines = 0
        action.addTarget(self, action: #selector(copyLink), for: .touchUpInside)
        action.setTitle(String(localized: "Copy link"), for: .normal)
        action.accessibilityIdentifier = "copySharedLink"
        action.isHidden = true
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)
        done.setTitle(String(localized: "Done"), for: .normal)
        done.accessibilityIdentifier = "finishSharing"
        let stack = UIStackView(arrangedSubviews: [label, action, done])
        stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                                     stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
                                     stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                                     action.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                                     done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        Task { @MainActor in
            guard let link = await sharedLink() else {
                fail(String(localized: "Share a YouTube or SoundCloud link to open it in DriftLoom.")); return
            }
            self.link = link
            if let inbox = SharedLinkInbox.configured() {
                do {
                    try inbox.save(link)
                    label.text = String(localized: "Link saved. Open DriftLoom to choose when to play it.")
                    label.accessibilityIdentifier = "sharedLinkSaved"
                    return
                } catch {
                    label.text = String(localized: "Couldn't save this link. Copy it and paste it in DriftLoom.")
                }
            } else {
                label.text = String(localized: "Copy this link, then open DriftLoom and paste it in Search.")
            }
            action.isHidden = false
        }
    }

    /// A shared URL, or the first supported link in shared text (the YouTube app shares both).
    private func sharedLink() async -> URL? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, SharedLink.isSupported(url) { return url }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = SharedLink.firstSupportedURL(in: text) { return url }
        }
        return nil
    }

    @objc private func copyLink() {
        guard let link else { return }
        UIPasteboard.general.url = link
        label.text = String(localized: "Link copied. Open DriftLoom and paste it in Search.")
        action.isHidden = true
    }

    @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }

    private func fail(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "DriftLoomShare", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}
