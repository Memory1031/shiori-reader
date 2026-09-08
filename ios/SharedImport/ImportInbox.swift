import Darwin
import Foundation

enum ImportIssue: String, Error {
  case unreadable, tooLarge, unsupported, multiple, busy, storage, cancelled
}

final class ImportCancellation {
  private let lock = NSLock()
  private var value = false
  func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }
  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

/// One durable receipt shared by app and extension. flock protects the slot
/// across processes; unfinished copies are never exposed to the Dart reader.
final class ImportInbox {
  static let maxBytes = 128 * 1024 * 1024
  let root: URL
  init() throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "ShioriImportGroup") as? String,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else {
      throw ImportIssue.storage
    }
    root = container.appendingPathComponent("ImportInbox", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var url = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
  // Tests inject an isolated application-owned directory; production uses
  // the entitlement-backed group container above.
  init(directory: URL) throws {
    root = directory
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  private func locked<T>(_ body: () throws -> T) throws -> T {
    let fd = Darwin.open(root.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw ImportIssue.storage }
    defer { Darwin.close(fd) }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ImportIssue.busy }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }
  func pending() throws -> [String: Any]? {
    try locked {
      // No writer can be running while this lock is held.
      try? FileManager.default.removeItem(at: root.appendingPathComponent("working"))
      let dir = root.appendingPathComponent("pending")
      guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
      guard
        var value = try JSONSerialization.jsonObject(
          with: Data(contentsOf: dir.appendingPathComponent("receipt.json"))) as? [String: Any],
        value["id"] is String, value["name"] is String, value["size"] is NSNumber
      else { throw ImportIssue.storage }
      value["path"] = dir.appendingPathComponent("payload").path
      return value
    }
  }
  func acknowledge(_ id: String) throws {
    try locked {
      let dir = root.appendingPathComponent("pending")
      guard FileManager.default.fileExists(atPath: dir.path) else { return }
      guard
        let value = try JSONSerialization.jsonObject(
          with: Data(contentsOf: dir.appendingPathComponent("receipt.json"))) as? [String: Any]
      else { throw ImportIssue.storage }
      if value["id"] as? String == id { try FileManager.default.removeItem(at: dir) }
    }
  }
  func stage(
    _ url: URL, displayName: String? = nil, cancellation: ImportCancellation,
    progress: (Int) -> Void
  ) throws {
    try locked {
      let fm = FileManager.default
      let final = root.appendingPathComponent("pending")
      guard !fm.fileExists(atPath: final.path) else { throw ImportIssue.busy }
      guard url.isFileURL else { throw ImportIssue.unsupported }
      let name = displayName ?? url.lastPathComponent
      let ext = (name as NSString).pathExtension.lowercased()
      guard ["txt", "epub"].contains(ext) else { throw ImportIssue.unsupported }
      let dir = root.appendingPathComponent("working")
      try? fm.removeItem(at: dir)
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? fm.removeItem(at: dir) }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      var coordinationError: NSError?
      var copyError: Error?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
        readable in
        do {
          guard let input = InputStream(url: readable),
            let output = OutputStream(url: dir.appendingPathComponent("payload"), append: false)
          else { throw ImportIssue.unreadable }
          input.open()
          output.open()
          defer {
            input.close()
            output.close()
          }
          var buffer = [UInt8](repeating: 0, count: 64 * 1024)
          var size = 0
          while true {
            if cancellation.isCancelled { throw ImportIssue.cancelled }
            let n = input.read(&buffer, maxLength: buffer.count)
            if n < 0 { throw ImportIssue.unreadable }
            if n == 0 { break }
            size += n
            if size > Self.maxBytes { throw ImportIssue.tooLarge }
            var offset = 0
            while offset < n {
              let wrote = buffer.withUnsafeBufferPointer { ptr in
                output.write(ptr.baseAddress! + offset, maxLength: n - offset)
              }
              if wrote <= 0 { throw ImportIssue.storage }
              offset += wrote
            }
            progress(size)
          }
          if size == 0 { throw ImportIssue.unreadable }
          if cancellation.isCancelled { throw ImportIssue.cancelled }
          let receipt: [String: Any] = ["id": UUID().uuidString, "name": name, "size": size]
          try JSONSerialization.data(withJSONObject: receipt).write(
            to: dir.appendingPathComponent("receipt.json"), options: .atomic)
          try fm.moveItem(at: dir, to: final)
        } catch { copyError = error }
      }
      if let error = coordinationError { throw error }
      if let error = copyError { throw error }
    }
  }
}
