import UIKit
import UniformTypeIdentifiers

/// Only remote links use the extension. Readable files are declared by the main
/// app's CFBundleDocumentTypes so the system opens the app directly with a file
/// URL. A Share extension cannot launch its containing app through a supported API.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first,
              provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            finish(success: false, message: localized("无法读取分享连结"))
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            // `item` is NSSecureCoding, which is not Sendable: take the URL out before the hop.
            let url = item as? URL
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(success: false, message: error.localizedDescription)
                    return
                }
                guard let url,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    self.finish(success: false, message: localized("无法读取分享连结"))
                    return
                }
                self.enqueue(url)
            }
        }
    }

    private func enqueue(_ url: URL) {
        do {
            guard let defaults = UserDefaults(suiteName: "group.com.zhangruilin.yuedureader") else {
                finish(success: false, message: localized("无法储存分享连结"))
                return
            }
            let encoded = try JSONEncoder().encode(LinkPayload(remoteURLString: url.absoluteString))
            let key = "shared_import_items_queue"
            var pending = defaults.array(forKey: key) as? [Data] ?? []
            pending.append(encoded)
            defaults.set(pending, forKey: key)
            defaults.synchronize()
            finish(success: true, message: localized("连结已储存，下次开启阅读时汇入。"))
        } catch {
            finish(success: false, message: error.localizedDescription)
        }
    }

    private func finish(success: Bool, message: String) {
        let alert = UIAlertController(title: localized(success ? "连结已储存" : "汇入失败"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("关闭"), style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        present(alert, animated: true)
    }
}

/// Matches the main app's existing queue format, including older installations.
private struct LinkPayload: Encodable {
    var id = UUID().uuidString
    var storageKind = "remoteURL"
    var remoteURLString: String
    var createdAt = Date()
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
