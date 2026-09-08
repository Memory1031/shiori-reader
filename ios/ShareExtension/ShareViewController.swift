import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let button = UIButton(type: .system)
  private let cancellation = ImportCancellation()
  private var started = false
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = NSLocalizedString("receiving", comment: "")
    button.setTitle(NSLocalizedString("cancel", comment: ""), for: .normal)
    button.addTarget(self, action: #selector(close), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [label, button])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {
      $0.attachments ?? []
    }
    guard providers.count == 1 else {
      finish("multiple")
      return
    }
    let provider = providers[0]
    let epub = UTType(filenameExtension: "epub")?.identifier ?? "org.idpf.epub-container"
    guard
      let type = [epub, UTType.plainText.identifier].first(where: {
        provider.hasItemConformingToTypeIdentifier($0)
      })
    else {
      finish("unsupported")
      return
    }
    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
      // The provider URL only lives for this callback: finish the streaming
      // copy here before returning, never dispatch the URL elsewhere.
      guard let url = url else {
        self.finish("unreadable")
        return
      }
      do {
        let name =
          ["txt", "epub"].contains(url.pathExtension.lowercased())
          ? url.lastPathComponent : provider.suggestedName
        try ImportInbox().stage(url, displayName: name, cancellation: self.cancellation) { _ in }
        self.finish("received")
      } catch { self.finish((error as? ImportIssue)?.rawValue ?? "unreadable") }
    }
  }
  private func finish(_ key: String) {
    DispatchQueue.main.async {
      self.label.text = NSLocalizedString(key, comment: "")
      self.button.setTitle(NSLocalizedString("done", comment: ""), for: .normal)
    }
  }
  @objc private func close() {
    cancellation.cancel()
    // Never try to force-open the host app; it consumes the receipt on resume.
    extensionContext?.completeRequest(returningItems: nil)
  }
}
