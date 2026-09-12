import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let button = UIButton(type: .system)
  private enum State { case idle, receiving, cancelling, finished }
  private var state = State.idle
  private var batch: ImportProviderBatch?
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
    guard state == .idle else { return }
    state = .receiving
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {
      $0.attachments ?? []
    }
    let batch = ImportProviderBatch()
    self.batch = batch
    batch.start(providers, progress: { [weak self] index, count in
      DispatchQueue.main.async {
        guard let self = self, self.state == .receiving else { return }
        self.label.text = String(format: NSLocalizedString("receiving_progress", comment: ""), index, count)
      }
    }, completion: { [weak self] outcome in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let wasCancelling = self.state == .cancelling
        self.state = .finished
        self.batch = nil
        // Completion follows session cleanup and flock release, never the tap.
        if wasCancelling {
          switch outcome {
          case .success, .failure(.cancelled):
            self.extensionContext?.completeRequest(returningItems: nil)
            return
          case .failure: break // Keep cleanup/storage failures visible.
          }
        }
        switch outcome {
        case .success(let count):
          self.label.text = count == 1
            ? NSLocalizedString("received", comment: "")
            : String(format: NSLocalizedString("received_multiple", comment: ""), count)
        case .failure(let issue):
          self.label.text = NSLocalizedString(issue.rawValue, comment: "")
        }
        self.button.isEnabled = true
        self.button.setTitle(NSLocalizedString("done", comment: ""), for: .normal)
      }
    })
  }
  @objc private func close() {
    switch state {
    case .receiving:
      state = .cancelling
      label.text = NSLocalizedString("cancelling", comment: "")
      button.isEnabled = false
      batch?.cancel()
    case .cancelling: break
    case .idle, .finished:
      state = .finished
      // Never force-open Runner; it consumes the batch on its next resume.
      extensionContext?.completeRequest(returningItems: nil)
    }
  }
}
