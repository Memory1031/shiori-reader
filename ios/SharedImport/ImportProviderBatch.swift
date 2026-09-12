import Foundation
import UniformTypeIdentifiers

/// A narrow seam for deterministic provider-chain tests, not a second inbox.
protocol ImportFileProvider {
  var suggestedName: String? { get }
  func supports(_ type: String) -> Bool
  func loadFile(_ type: String, completion: @escaping (URL?, Error?) -> Void) -> Progress
}

extension NSItemProvider: ImportFileProvider {
  func supports(_ type: String) -> Bool { hasItemConformingToTypeIdentifier(type) }
  func loadFile(_ type: String, completion: @escaping (URL?, Error?) -> Void) -> Progress {
    loadFileRepresentation(forTypeIdentifier: type, completionHandler: completion)
  }
}

struct ImportProviderSelection {
  static let epub = UTType(filenameExtension: "epub")?.identifier ?? "org.idpf.epub-container"
  let provider: ImportFileProvider
  let type: String
  var fileExtension: String { type == Self.epub ? "epub" : "txt" }

  static func prepare(_ providers: [ImportFileProvider], limits: ImportLimits,
                      cancellation: ImportCancellation) throws -> [Self] {
    try limits.checkCount(providers.count)
    return try providers.map { provider in
      try cancellation.check()
      guard let type = [epub, UTType.plainText.identifier].first(where: { provider.supports($0) })
      else { throw ImportIssue.unsupported }
      return Self(provider: provider, type: type)
    }
  }

  func displayName(for url: URL, index: Int) -> String {
    let ext = fileExtension
    if url.pathExtension.lowercased() == ext { return url.lastPathComponent }
    if let name = provider.suggestedName, !name.isEmpty {
      let suffix = (name as NSString).pathExtension.lowercased()
      if suffix == ext { return name }
      if suffix.isEmpty { return name + "." + ext }
    }
    return String(format: "Book-%03d.%@", index + 1, ext)
  }
}

/// Serial provider materialization. All session state belongs to worker.
/// Cancellation alone is thread-safe and may interrupt a running stream.
final class ImportProviderBatch {
  private let worker = DispatchQueue(label: "dev.shiori.reader.share-import", qos: .userInitiated)
  private let workerKey = DispatchSpecificKey<Bool>()
  private let cancellation = ImportCancellation()
  private let makeInbox: () throws -> ImportInbox
  private let limits: ImportLimits
  private var session: ImportInbox.Session?
  private var selections: [ImportProviderSelection] = []
  private var activeLoad: Progress?
  private var loadingIndex: Int?
  private var started = false
  private var finished = false
  private var progress: ((Int, Int) -> Void)?
  private var completion: ((Result<Int, ImportIssue>) -> Void)?

  init(limits: ImportLimits = .production, makeInbox: @escaping () throws -> ImportInbox = { try ImportInbox() }) {
    self.limits = limits
    self.makeInbox = makeInbox
    worker.setSpecific(key: workerKey, value: true)
  }

  func start(_ providers: [ImportFileProvider], progress: @escaping (Int, Int) -> Void,
             completion: @escaping (Result<Int, ImportIssue>) -> Void) {
    worker.async {
      guard !self.started else { return }
      self.started = true
      self.progress = progress
      self.completion = completion
      do {
        self.selections = try ImportProviderSelection.prepare(
          providers, limits: self.limits, cancellation: self.cancellation)
        self.session = try self.makeInbox().beginBatch(
          expectedCount: self.selections.count, cancellation: self.cancellation)
        self.receive(at: 0)
      } catch { self.finish(.failure((error as? ImportIssue) ?? .storage)) }
    }
  }

  func cancel() {
    cancellation.cancel()
    worker.async {
      // Do not finish here: a provider still owns its callback and temporary URL.
      self.activeLoad?.cancel()
    }
  }

  private func receive(at index: Int) {
    guard !finished else { return }
    activeLoad = nil
    do {
      try cancellation.check()
      guard let session = session else { throw ImportIssue.storage }
      if index == selections.count {
        try session.commit()
        finish(.success(selections.count))
        return
      }
      let selection = selections[index]
      loadingIndex = index
      progress?(index + 1, selections.count)
      activeLoad = selection.provider.loadFile(selection.type) { url, error in
        // Callback-scoped URL: this block MUST finish append before returning.
        // Handle even a synchronously completing provider without queue deadlock.
        let consume = {
          guard !self.finished, self.loadingIndex == index else { return }
          self.loadingIndex = nil
          self.activeLoad = nil
          do {
            try self.cancellation.check()
            guard error == nil, let url = url else { throw ImportIssue.unreadable }
            try session.append(url: url, displayName: selection.displayName(for: url, index: index))
            // Only the next index crosses the async boundary, never this URL.
            self.worker.async { self.receive(at: index + 1) }
          } catch { self.finish(.failure((error as? ImportIssue) ?? .unreadable)) }
        }
        if DispatchQueue.getSpecific(key: self.workerKey) == true { consume() }
        else { self.worker.sync(execute: consume) }
      }
      if finished { activeLoad = nil }
    } catch { finish(.failure((error as? ImportIssue) ?? .storage)) }
  }

  private func finish(_ result: Result<Int, ImportIssue>) {
    guard !finished else { return }
    var outcome = result
    do { try session?.abort() }
    catch { outcome = .failure(.storage) }
    // Cleanup and lock release precede completion, including the cancel path.
    session = nil
    activeLoad = nil
    loadingIndex = nil
    selections = []
    progress = nil
    finished = true
    let callback = completion
    completion = nil
    callback?(outcome)
  }
}
