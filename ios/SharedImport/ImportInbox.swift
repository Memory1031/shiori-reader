import CoreFoundation
import Darwin
import Foundation

enum ImportIssue: String, Error {
  case unreadable, tooLarge, batchLimit, unsupported, multiple, busy, storage, cancelled
}

struct ImportLimits {
  let maxFiles: Int
  let maxFileBytes: Int64
  let maxBatchBytes: Int64
  static let production = ImportLimits(
    maxFiles: 64, maxFileBytes: 128 * 1024 * 1024, maxBatchBytes: 512 * 1024 * 1024)

  func checkCount(_ count: Int) throws {
    guard count > 0 else { throw ImportIssue.unreadable }
    guard count <= maxFiles else { throw ImportIssue.batchLimit }
  }
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
  func check() throws {
    if isCancelled { throw ImportIssue.cancelled }
  }
}

/// One app-group batch. A session owns flock across all provider callbacks;
/// only working -> pending publishes files. Call session methods serially.
final class ImportInbox {
  let root: URL
  let limits: ImportLimits
  private let fm = FileManager.default
  private static let receiptBytes: Int64 = 64 * 1024

  convenience init() throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "ShioriImportGroup") as? String,
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { throw ImportIssue.storage }
    try self.init(directory: container.appendingPathComponent("ImportInbox", isDirectory: true))
    var url = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  // Tests own an isolated directory and small limits; app defaults never change.
  init(directory: URL, limits: ImportLimits = .production) throws {
    guard directory.isFileURL, (1...64).contains(limits.maxFiles),
      (1...ImportLimits.production.maxFileBytes).contains(limits.maxFileBytes),
      (1...ImportLimits.production.maxBatchBytes).contains(limits.maxBatchBytes)
    else { throw ImportIssue.storage }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    root = directory.standardizedFileURL.resolvingSymlinksInPath()
    self.limits = limits
    try requireDirectory(root)
  }

  private struct Receipt {
    let directory: URL
    let id: String
    let name: String
    let size: Int64
    let order: Int
    var channelValue: [String: Any] {
      ["id": id, "name": name, "size": size,
       "path": directory.appendingPathComponent("payload").path]
    }
  }

  fileprivate final class Lock {
    private var fd: Int32
    init(_ url: URL) throws {
      fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard fd >= 0 else { throw ImportIssue.storage }
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        let issue: ImportIssue = errno == EWOULDBLOCK ? .busy : .storage
        Darwin.close(fd)
        fd = -1
        throw issue
      }
    }
    func release() {
      if fd >= 0 {
        flock(fd, LOCK_UN)
        Darwin.close(fd)
        fd = -1
      }
    }
    deinit { release() }
  }

  private func acquire() throws -> Lock {
    try requireDirectory(root)
    let url = root.appendingPathComponent("lock")
    if let info = try node(url), !isType(info, mode_t(S_IFREG)) { throw ImportIssue.storage }
    return try Lock(url)
  }
  private func locked<T>(_ body: () throws -> T) throws -> T {
    let lock = try acquire()
    defer { lock.release() }
    do { return try body() }
    catch let issue as ImportIssue { throw issue }
    catch { throw ImportIssue.storage }
  }

  func pending() throws -> [[String: Any]] {
    try locked {
      try recover()
      return try inspect().map { $0.channelValue }
    }
  }
  func acknowledge(_ id: String) throws {
    try locked {
      try recover()
      guard let receipt = try inspect().first(where: { $0.id == id }) else { return }
      let trash = root.appendingPathComponent("ack-trash-\(UUID().uuidString)")
      // Lookup by metadata only; caller ids never become paths.
      try rename(receipt.directory, trash)
      let pending = root.appendingPathComponent("pending")
      if try node(pending) != nil { try sync(pending, directory: true) }
      try sync(root, directory: true)
      try removeEmptyPending()
      try? removeTemporary(trash)
    }
  }

  func beginBatch(expectedCount: Int, cancellation: ImportCancellation) throws -> Session {
    try limits.checkCount(expectedCount)
    try cancellation.check()
    let lock = try acquire()
    do {
      try recover()
      guard try inspect().isEmpty else { throw ImportIssue.busy }
      try cancellation.check()
      try fm.createDirectory(at: root.appendingPathComponent("working"),
                             withIntermediateDirectories: false)
      return Session(inbox: self, lock: lock, expectedCount: expectedCount,
                     cancellation: cancellation)
    } catch {
      lock.release()
      throw (error as? ImportIssue) ?? ImportIssue.storage
    }
  }

  func stage(_ urls: [URL], cancellation: ImportCancellation, progress: (Int64) -> Void) throws {
    try limits.checkCount(urls.count)
    // Validate every picker URL before working or any InputStream is created.
    for url in urls {
      try validate(url, name: url.lastPathComponent, cancellation: cancellation)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        Int64(size) > limits.maxFileBytes { throw ImportIssue.tooLarge }
      try cancellation.check()
    }
    let session = try beginBatch(expectedCount: urls.count, cancellation: cancellation)
    defer { try? session.abort() }
    for url in urls { try session.append(url: url, progress: progress) }
    try session.commit()
  }
  func stage(_ url: URL, displayName: String? = nil, cancellation: ImportCancellation,
             progress: (Int64) -> Void) throws {
    if displayName == nil {
      try stage([url], cancellation: cancellation, progress: progress)
      return
    }
    try validate(url, name: displayName!, cancellation: cancellation)
    let session = try beginBatch(expectedCount: 1, cancellation: cancellation)
    defer { try? session.abort() }
    try session.append(url: url, displayName: displayName, progress: progress)
    try session.commit()
  }
  private func validate(_ url: URL, name: String, cancellation: ImportCancellation) throws {
    try cancellation.check()
    guard url.isFileURL, !name.isEmpty,
      ["txt", "epub"].contains((name as NSString).pathExtension.lowercased())
    else { throw ImportIssue.unsupported }
  }

  final class Session {
    private let inbox: ImportInbox
    private let lock: Lock
    private let expectedCount: Int
    private let cancellation: ImportCancellation
    private var nextOrder = 0
    private var total: Int64 = 0
    private var reported: Int64 = 0
    private var finished = false
    private var working: URL { inbox.root.appendingPathComponent("working") }

    fileprivate init(inbox: ImportInbox, lock: Lock, expectedCount: Int,
                     cancellation: ImportCancellation) {
      self.inbox = inbox
      self.lock = lock
      self.expectedCount = expectedCount
      self.cancellation = cancellation
    }
    func append(url: URL, displayName: String? = nil, progress: (Int64) -> Void = { _ in }) throws {
      guard !finished else { throw ImportIssue.storage }
      do {
        guard nextOrder < expectedCount else { throw ImportIssue.batchLimit }
        let name = displayName ?? url.lastPathComponent
        try inbox.validate(url, name: name, cancellation: cancellation)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: Error?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
          readable in
          do {
            try copy(readable, name: name, progress: progress)
            copied = true
          } catch { copyError = error }
        }
        if let error = copyError { throw error }
        guard coordinationError == nil, copied else { throw ImportIssue.unreadable }
        try cancellation.check()
        nextOrder += 1
      } catch {
        try abort()
        throw (error as? ImportIssue) ?? ImportIssue.storage
      }
    }
    private func copy(_ url: URL, name: String, progress: (Int64) -> Void) throws {
      try cancellation.check()
      let id = UUID().uuidString
      let dir = working.appendingPathComponent(String(format: "item-%04d-%@", nextOrder, id))
      try inbox.fm.createDirectory(at: dir, withIntermediateDirectories: false)
      let payload = dir.appendingPathComponent("payload")
      guard let input = InputStream(url: url), let output = OutputStream(url: payload, append: false)
      else { throw ImportIssue.unreadable }
      var size: Int64 = 0
      do {
        input.open()
        output.open()
        defer { input.close(); output.close() }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
          try cancellation.check()
          let n = input.read(&buffer, maxLength: buffer.count)
          try cancellation.check()
          guard n >= 0 else { throw ImportIssue.unreadable }
          if n == 0 { break }
          size += Int64(n)
          total += Int64(n)
          guard size <= inbox.limits.maxFileBytes else { throw ImportIssue.tooLarge }
          guard total <= inbox.limits.maxBatchBytes else { throw ImportIssue.batchLimit }
          var offset = 0
          while offset < n {
            try cancellation.check()
            let wrote = buffer.withUnsafeBufferPointer {
              output.write($0.baseAddress! + offset, maxLength: n - offset)
            }
            guard wrote > 0 else { throw ImportIssue.storage }
            offset += wrote
          }
          if total - reported >= 1024 * 1024 { reported = total; progress(total) }
        }
        guard size > 0 else { throw ImportIssue.unreadable }
      }
      // Streams are closed before fsync, metadata, or append returning.
      try inbox.sync(payload)
      let receipt: [String: Any] = ["id": id, "name": name, "size": size, "order": nextOrder]
      let data = try JSONSerialization.data(withJSONObject: receipt)
      guard Int64(data.count) <= ImportInbox.receiptBytes else { throw ImportIssue.unreadable }
      let metadata = dir.appendingPathComponent("receipt.json")
      try data.write(to: metadata)
      try inbox.sync(metadata)
      try inbox.sync(dir, directory: true)
    }
    func commit() throws {
      guard !finished else { throw ImportIssue.storage }
      do {
        try cancellation.check()
        guard nextOrder == expectedCount, total <= inbox.limits.maxBatchBytes,
          try inbox.node(inbox.root.appendingPathComponent("pending")) == nil
        else { throw ImportIssue.storage }
        let receipts = try inbox.inspectBatch(working)
        guard receipts.count == expectedCount,
          receipts.map({ $0.order }) == Array(0..<expectedCount),
          receipts.reduce(Int64(0), { $0 + $1.size }) == total
        else { throw ImportIssue.storage }
        try inbox.sync(working, directory: true)
        try cancellation.check()
        try inbox.rename(working, inbox.root.appendingPathComponent("pending"))
        // Publication wins even when the following directory sync fails.
        finished = true
        defer { lock.release() }
        try inbox.sync(inbox.root, directory: true)
      } catch {
        try abort()
        throw (error as? ImportIssue) ?? ImportIssue.storage
      }
    }
    func abort() throws {
      guard !finished else { return }
      finished = true
      // Failed cleanup is retried by recovery; never remove published pending.
      defer { lock.release() }
      do { try inbox.removeTemporary(working) }
      catch { throw ImportIssue.storage }
    }
    deinit { try? abort() }
  }

  private func inspect() throws -> [Receipt] {
    let pending = root.appendingPathComponent("pending")
    guard try node(pending) != nil else { return [] }
    let entries = try children(pending)
    if entries.contains(where: { ["receipt.json", "payload"].contains($0.lastPathComponent) }) {
      let receipt = try readReceipt(pending, legacy: true)
      guard receipt.size <= limits.maxBatchBytes else { throw ImportIssue.storage }
      return [receipt]
    }
    return try inspectBatch(pending)
  }
  private func inspectBatch(_ directory: URL) throws -> [Receipt] {
    let entries = try children(directory)
    guard entries.count <= limits.maxFiles else { throw ImportIssue.storage }
    let receipts = try entries.map { url -> Receipt in
      guard Self.itemName(url.lastPathComponent) else { throw ImportIssue.storage }
      return try readReceipt(url, legacy: false)
    }
    guard Set(receipts.map { $0.id }).count == receipts.count,
      Set(receipts.map { $0.order }).count == receipts.count,
      receipts.reduce(Int64(0), { $0 + $1.size }) <= limits.maxBatchBytes
    else { throw ImportIssue.storage }
    return receipts.sorted { $0.order < $1.order }
  }
  private func readReceipt(_ directory: URL, legacy: Bool) throws -> Receipt {
    guard Set(try children(directory).map { $0.lastPathComponent }) == ["payload", "receipt.json"]
    else { throw ImportIssue.storage }
    let metadata = directory.appendingPathComponent("receipt.json")
    let payload = directory.appendingPathComponent("payload")
    let metadataSize = try regularSize(metadata)
    guard (1...Self.receiptBytes).contains(metadataSize),
      let json = try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any],
      let id = json["id"] as? String, !id.isEmpty,
      let name = json["name"] as? String, !name.isEmpty
    else { throw ImportIssue.storage }
    let size = try integer(json["size"])
    let order = legacy ? Int64(0) : (try integer(json["order"]))
    guard (1...limits.maxFileBytes).contains(size), (0..<Int64(limits.maxFiles)).contains(order),
      try regularSize(payload) == size else { throw ImportIssue.storage }
    return Receipt(directory: directory, id: id, name: name, size: size, order: Int(order))
  }
  private func integer(_ value: Any?) throws -> Int64 {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      !["f", "d"].contains(String(cString: number.objCType)),
      let integer = Int64(number.stringValue) else { throw ImportIssue.storage }
    return integer
  }
  private func recover() throws {
    try removeTemporary(root.appendingPathComponent("working"))
    for url in try children(root) where Self.trashName(url.lastPathComponent) {
      try? removeTemporary(url)
    }
    try removeEmptyPending()
  }
  private func removeEmptyPending() throws {
    let pending = root.appendingPathComponent("pending")
    if try node(pending) != nil, try children(pending).isEmpty {
      try fm.removeItem(at: pending)
      try sync(root, directory: true)
    }
  }
  private static func itemName(_ name: String) -> Bool {
    name.range(of: "^item-[0-9]{4}-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
               options: .regularExpression) != nil
  }
  private static func trashName(_ name: String) -> Bool {
    name.hasPrefix("ack-trash-") && UUID(uuidString: String(name.dropFirst(10))) != nil
  }
  private func node(_ url: URL) throws -> stat? {
    guard url.standardizedFileURL.path == root.path ||
      url.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw ImportIssue.storage }
    var info = stat()
    if lstat(url.path, &info) == 0 { return info }
    if errno == ENOENT { return nil }
    throw ImportIssue.storage
  }
  private func isType(_ info: stat, _ type: mode_t) -> Bool {
    info.st_mode & mode_t(S_IFMT) == type
  }
  private func requireDirectory(_ url: URL) throws {
    guard let info = try node(url), isType(info, mode_t(S_IFDIR)),
      url.resolvingSymlinksInPath().path == url.standardizedFileURL.path
    else { throw ImportIssue.storage }
  }
  private func children(_ url: URL) throws -> [URL] {
    try requireDirectory(url)
    return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
  }
  private func regularSize(_ url: URL) throws -> Int64 {
    guard let info = try node(url), isType(info, mode_t(S_IFREG)),
      url.resolvingSymlinksInPath().path == url.standardizedFileURL.path
    else { throw ImportIssue.storage }
    return info.st_size
  }
  private func removeTemporary(_ url: URL) throws {
    guard url.deletingLastPathComponent().path == root.path,
      url.lastPathComponent == "working" || Self.trashName(url.lastPathComponent)
    else { throw ImportIssue.storage }
    try unlinkTree(url)
  }
  private func unlinkTree(_ url: URL) throws {
    guard let info = try node(url) else { return }
    if isType(info, mode_t(S_IFDIR)) {
      for child in try children(url) { try unlinkTree(child) }
    }
    // lstat never recurses through symlinks; removeItem unlinks the link itself.
    try fm.removeItem(at: url)
  }
  private func rename(_ from: URL, _ to: URL) throws {
    guard Darwin.rename(from.path, to.path) == 0 else { throw ImportIssue.storage }
  }
  private func sync(_ url: URL, directory: Bool = false) throws {
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw ImportIssue.storage }
    defer { Darwin.close(fd) }
    if fsync(fd) != 0 {
      if directory && (errno == EINVAL || errno == ENOTSUP) { return }
      throw ImportIssue.storage
    }
  }
}
