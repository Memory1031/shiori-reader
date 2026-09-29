import UIKit
import UniformTypeIdentifiers

/// Native collection only: the host closes this request; Runner imports later.
final class ShareViewController: UIViewController {
  enum State {
    case idle
    case receiving(index: Int, count: Int)
    case received(ImportReceiptSummary)
    case cancelling
    case failed(ImportIssue)
    case terminated
  }
  private(set) var state = State.idle
  // Narrow injection seams for native state/lifecycle tests and previews.
  var makeReceiver: () -> ImportBatchReceiving = { ImportProviderBatch() }
  var inputProviders: [ImportFileProvider]?
  var requestCompletion: (() -> Void)?
  private var batch: ImportBatchReceiving?
  private var names: [String] = []
  private let brand = UILabel()
  private let heading = UILabel()
  private let detail = UILabel()
  private let total = UILabel()
  private let files = UIStackView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let activity = UILabel()
  private let button = UIButton(type: .system)
  private let content = UIStackView()
  private var lastAnnouncement: String?

  private static let paper = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0.09, green: 0.11, blue: 0.10, alpha: 1)
    : UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1) }
  private static let card = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0.15, green: 0.17, blue: 0.16, alpha: 1) : .white }
  private static let accent = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0.66, green: 0.81, blue: 0.70, alpha: 1)
    : UIColor(red: 0.22, green: 0.38, blue: 0.28, alpha: 1) }
  private func text(_ key: String) -> String {
    NSLocalizedString(key, bundle: Bundle(for: ShareViewController.self), comment: "")
  }
  private func countText(_ key: String, _ count: Int) -> String {
    count == 1 ? text(key + "_one") : String(format: text(key), count)
  }
  private func label(_ label: UILabel, style: UIFont.TextStyle) {
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textColor = .label
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Self.paper
    label(brand, style: .headline)
    brand.textColor = Self.accent
    label(heading, style: .title1)
    heading.accessibilityTraits.insert(.header)
    label(detail, style: .body)
    label(total, style: .headline)
    label(activity, style: .subheadline)
    let mark = UIImageView(image: UIImage(systemName: "bookmark.fill"))
    mark.tintColor = Self.accent
    mark.contentMode = .scaleAspectFit
    mark.isAccessibilityElement = false
    mark.widthAnchor.constraint(equalToConstant: 22).isActive = true
    let identity = UIStackView(arrangedSubviews: [mark, brand])
    identity.spacing = 10
    identity.alignment = .center
    let progress = UIStackView(arrangedSubviews: [spinner, activity])
    progress.spacing = 10
    progress.alignment = .center
    files.axis = .vertical
    files.spacing = 10
    content.axis = .vertical
    content.spacing = 20
    for child in [identity, heading, progress, files, total, detail] {
      content.addArrangedSubview(child)
    }
    let scroll = UIScrollView()
    scroll.alwaysBounceVertical = false
    scroll.addSubview(content)
    view.addSubview(scroll)
    view.addSubview(button)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 0
    button.titleLabel?.textAlignment = .center
    button.backgroundColor = Self.accent
    button.setTitleColor(Self.paper, for: .normal)
    button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
    button.layer.cornerRadius = 16
    button.accessibilityIdentifier = "share-action"
    button.addTarget(self, action: #selector(close), for: .touchUpInside)
    for child in [scroll, content, button] { child.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      scroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -20),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      button.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
      button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
    ])
    display(state)
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard case .idle = state else { return }
    let providers: [ImportFileProvider] = inputProviders ??
      (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    names = providers.enumerated().map { index, provider in
      provider.suggestedName ?? String(format: text("unnamed_file"), index + 1)
    }
    display(.receiving(index: 1, count: providers.count))
    let receiver = makeReceiver()
    batch = receiver
    receiver.start(providers, progress: { [weak self] index, count in
      DispatchQueue.main.async {
        guard let self = self, case .receiving = self.state else { return }
        self.display(.receiving(index: index, count: count))
      }
    }, completion: { [weak self] outcome in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch self.state {
        case .receiving, .cancelling: break
        default: return
        }
        self.batch = nil
        switch outcome {
        case .success(let summary):
          // Publication wins over a late cancel; show what actually happened.
          self.display(.received(summary))
        case .failure(.cancelled): self.terminate()
        case .failure(let issue): self.display(.failed(issue))
        }
      }
    })
  }

  /// State rendering is also used by the native preview; it never starts IO.
  func display(_ next: State) {
    if case .terminated = state { return }
    state = next
    guard isViewLoaded else { return }
    brand.text = text("brand_collect")
    total.isHidden = true
    activity.isHidden = true
    spinner.stopAnimating()
    button.isEnabled = true
    button.setTitle(text("done"), for: .normal)
    var shownNames = names
    switch next {
    case .idle:
      heading.text = text("receiving")
      detail.text = text("receive_help")
    case .receiving(let index, let count):
      heading.text = countText("receiving_count", count)
      detail.text = text("receive_help")
      activity.text = String(format: text("receiving_progress"), index, count)
      activity.isHidden = false
      spinner.startAnimating()
      button.setTitle(text("cancel"), for: .normal)
    case .received(let summary):
      brand.text = text("brand_inbox")
      heading.text = "✓ " + countText("received_count", summary.names.count)
      detail.text = text("received_help")
      total.text = countText("pending_count", summary.pendingCount)
      total.isHidden = false
      shownNames = summary.names
    case .cancelling:
      heading.text = text("cancelling")
      detail.text = text("cancelling_help")
      spinner.startAnimating()
      button.setTitle(text("cancelling"), for: .normal)
      button.isEnabled = false
    case .failed(let issue):
      heading.text = text(issue == .inboxFull ? "inbox_full_title" : "error_title")
      detail.text = text(issue.rawValue)
      if issue != .publicationUncertain && issue != .storage {
        detail.text = (detail.text ?? "") + "\n\n" + text("previous_preserved")
      }
      shownNames = []
    case .terminated: return
    }
    showFiles(shownNames)
    // Announce phase transitions only, not per-file starts or byte callbacks.
    if let title = heading.text, title != lastAnnouncement {
      lastAnnouncement = title
      UIAccessibility.post(notification: .announcement, argument: title)
    }
  }
  private func showFiles(_ names: [String]) {
    files.arrangedSubviews.forEach { files.removeArrangedSubview($0); $0.removeFromSuperview() }
    files.isHidden = names.isEmpty
    for name in names.prefix(4) {
      let row = UIStackView()
      row.spacing = 14
      row.alignment = .center
      row.backgroundColor = Self.card
      row.layer.cornerRadius = 16
      row.isLayoutMarginsRelativeArrangement = true
      row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
      let icon = UIImageView(image: UIImage(systemName: "doc.text"))
      icon.tintColor = Self.accent
      icon.contentMode = .scaleAspectFit
      icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
      let title = UILabel()
      label(title, style: .body)
      title.text = name
      title.lineBreakMode = .byTruncatingMiddle
      title.numberOfLines = 2
      let kind = UILabel()
      label(kind, style: .caption1)
      let ext = (name as NSString).pathExtension.uppercased()
      kind.text = ["TXT", "EPUB"].contains(ext) ? ext : text("file_type")
      kind.textColor = Self.accent
      let copy = UIStackView(arrangedSubviews: [title, kind])
      copy.axis = .vertical
      copy.spacing = 4
      row.addArrangedSubview(icon)
      row.addArrangedSubview(copy)
      row.isAccessibilityElement = true
      row.accessibilityLabel = name + ", " + (kind.text ?? "")
      files.addArrangedSubview(row)
    }
    if names.count > 4 {
      let more = UILabel()
      label(more, style: .subheadline)
      more.text = countText("more_files", names.count - 4)
      more.accessibilityLabel = (more.text ?? "") + ": " + names.dropFirst(4).joined(separator: ", ")
      files.addArrangedSubview(more)
    }
  }
  @objc func close() {
    switch state {
    case .receiving:
      display(.cancelling)
      batch?.cancel()
    case .cancelling, .terminated: break
    case .idle, .received, .failed: terminate()
    }
  }
  private func terminate() {
    if case .terminated = state { return }
    state = .terminated
    button.isEnabled = false
    if let completion = requestCompletion { completion() }
    else { extensionContext?.completeRequest(returningItems: nil) }
  }
  deinit { batch?.cancel() }
}
