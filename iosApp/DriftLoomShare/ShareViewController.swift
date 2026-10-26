// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomActivity
import UIKit
import UniformTypeIdentifiers

/// "DriftLoom" in the share sheet: finds the YouTube or SoundCloud link that was shared and
/// opens it in the app through the driftloom://open URL scheme.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Opening in DriftLoom…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center; label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                                     label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !handled else { return }
        handled = true
        Task { @MainActor in
            guard let link = await sharedLink(), let appURL = SharedLink.appURL(for: link) else {
                fail("Share a YouTube or SoundCloud link to open it in DriftLoom."); return
            }
            if openContainingApp(appURL) { extensionContext?.completeRequest(returningItems: nil) }
            else { fail("DriftLoom couldn't be opened from here. Copy the link and paste it in DriftLoom.") }
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

    /// Share extensions have no public API to open their app, so ask the application object in
    /// the responder chain to open the app's own URL scheme.
    private func openContainingApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if NSStringFromClass(type(of: current)).contains("Application"), current.responds(to: selector) {
                typealias Open = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(current.method(for: selector), to: Open.self)(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func fail(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "DriftLoomShare", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}
