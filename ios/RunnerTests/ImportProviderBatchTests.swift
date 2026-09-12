import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import Runner

private final class FileProviderDouble: ImportFileProvider {
  var suggestedName: String?
  var types: Set<String> = [UTType.plainText.identifier]
  var url: URL?
  var error: Error?
  var deferred = false
  var asynchronous = false
  var onLoad: (() -> Void)?
  var afterCallback: (() -> Void)?
  var loadCount = 0
  var requestedTypes: [String] = []
  let progress = Progress(totalUnitCount: 1)
  private var callback: ((URL?, Error?) -> Void)?
  init(_ url: URL? = nil) { self.url = url }
  func supports(_ type: String) -> Bool { types.contains(type) }
  func loadFile(_ type: String, completion: @escaping (URL?, Error?) -> Void) -> Progress {
    loadCount += 1
    requestedTypes.append(type)
    callback = completion
    onLoad?()
    if !deferred {
      if asynchronous { DispatchQueue.global().async { self.deliver() } }
      else { deliver() }
    }
    return progress
  }
  func deliver() {
    let completion = callback
    callback = nil
    completion?(url, error)
    afterCallback?()
  }
}

final class ImportProviderBatchTests: XCTestCase {
  private var directory: URL!
  private var inbox: ImportInbox!
  private let limits = ImportLimits(maxFiles: 4, maxFileBytes: 128 * 1024, maxBatchBytes: 256 * 1024)
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    inbox = try ImportInbox(directory: directory.appendingPathComponent("inbox"), limits: limits)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
  private func provider(_ name: String, text: String = "offline") throws -> FileProviderDouble {
    let url = directory.appendingPathComponent(name)
    try Data(text.utf8).write(to: url)
    return FileProviderDouble(url)
  }
  private func run(_ providers: [ImportFileProvider]) -> Result<Int, ImportIssue> {
    let done = expectation(description: "provider batch")
    var result: Result<Int, ImportIssue>!
    let ownedInbox = inbox!
    let batch = ImportProviderBatch(limits: limits, makeInbox: { ownedInbox })
    batch.start(providers, progress: { _, _ in }, completion: { outcome in
      result = outcome
      done.fulfill()
    })
    wait(for: [done], timeout: 5)
    return result ?? .failure(.storage)
  }
  private func issue(_ expected: ImportIssue, _ outcome: Result<Int, ImportIssue>,
                     file: StaticString = #filePath, line: UInt = #line) {
    switch outcome {
    case .failure(let actual): XCTAssertEqual(actual, expected, file: file, line: line)
    case .success: XCTFail("Expected \(expected)", file: file, line: line)
    }
  }
  func testEPUBPreferredWhenProviderSupportsBothTypes() throws {
    let p = try provider("both.epub")
    p.types.insert(ImportProviderSelection.epub)
    XCTAssertEqual(try run([p]).get(), 1)
    XCTAssertEqual(p.requestedTypes, [ImportProviderSelection.epub])
  }
  func testUnsupportedLaterProviderRejectsWholeBatchBeforeLoad() throws {
    let first = try provider("first.txt")
    let second = FileProviderDouble()
    second.types = []
    issue(.unsupported, run([first, second]))
    XCTAssertEqual(first.loadCount, 0)
    XCTAssertEqual(second.loadCount, 0)
    XCTAssertTrue(try inbox.pending().isEmpty)
  }
  func test65ProvidersRejectedBeforeLoad() throws {
    let p = try provider("count.txt")
    let done = expectation(description: "count rejected")
    let batch = ImportProviderBatch(makeInbox: { XCTFail("Must preflight count first"); return self.inbox })
    batch.start(Array(repeating: p, count: 65), progress: { _, _ in }, completion: {
      self.issue(.batchLimit, $0)
      done.fulfill()
    })
    wait(for: [done], timeout: 5)
    XCTAssertEqual(p.loadCount, 0)
  }
  func testOrderAndDuplicatesArePreserved() throws {
    let first = try provider("z.txt")
    let next = try provider("a.txt")
    XCTAssertEqual(try run([first, next, first]).get(), 3)
    XCTAssertEqual(try inbox.pending().map { $0["name"] as! String }, ["z.txt", "a.txt", "z.txt"])
    XCTAssertEqual(first.loadCount, 2)
    XCTAssertEqual(Set(try inbox.pending().map { $0["id"] as! String }).count, 3)
  }
  func testTemporaryFilesCopiedBeforeEachCallbackReturns() throws {
    let first = try provider("temporary-a", text: "first")
    first.suggestedName = "first"
    let second = try provider("temporary-b", text: "second")
    second.suggestedName = "second.txt"
    let removed = expectation(description: "temporary files removed after callbacks")
    removed.expectedFulfillmentCount = 2
    for p in [first, second] {
      p.asynchronous = true
      let url = p.url!
      p.afterCallback = {
        try? FileManager.default.removeItem(at: url)
        removed.fulfill()
      }
    }
    XCTAssertEqual(try run([first, second]).get(), 2)
    wait(for: [removed], timeout: 5)
    XCTAssertFalse(FileManager.default.fileExists(atPath: first.url!.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: second.url!.path))
    let contents = try inbox.pending().map { try String(contentsOfFile: $0["path"] as! String) }
    XCTAssertEqual(contents, ["first", "second"])
  }
  func testDisplayNameFallbackMatchesSelectedType() {
    let p = FileProviderDouble()
    p.types = [ImportProviderSelection.epub]
    let selection = ImportProviderSelection(provider: p, type: ImportProviderSelection.epub)
    let temp = URL(fileURLWithPath: "/tmp/random")
    p.suggestedName = "suggested.epub"
    XCTAssertEqual(selection.displayName(for: URL(fileURLWithPath: "/tmp/Original.EPUB"), index: 0), "Original.EPUB")
    XCTAssertEqual(selection.displayName(for: temp, index: 0), "suggested.epub")
    p.suggestedName = "book"
    XCTAssertEqual(selection.displayName(for: temp, index: 0), "book.epub")
    p.suggestedName = nil
    XCTAssertEqual(selection.displayName(for: temp, index: 0), "Book-001.epub")
    p.suggestedName = "wrong.pdf"
    XCTAssertEqual(selection.displayName(for: temp, index: 1), "Book-002.epub")
    let text = ImportProviderSelection(provider: p, type: UTType.plainText.identifier)
    p.suggestedName = nil
    XCTAssertEqual(text.displayName(for: temp, index: 1), "Book-002.txt")
  }
  func testSecondFailureNeverLoadsThirdAndRollsBackFirst() throws {
    let first = try provider("first.txt")
    let failed = FileProviderDouble()
    let third = try provider("third.txt")
    issue(.unreadable, run([first, failed, third]))
    XCTAssertEqual(third.loadCount, 0)
    XCTAssertTrue(try inbox.pending().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.root.appendingPathComponent("working").path))
  }
  func testCancelWaitsForProviderCallbackThenCleansAndReleasesLock() throws {
    let first = try provider("first.txt")
    let pending = try provider("second.txt")
    pending.deferred = true
    let third = try provider("third.txt")
    let loaded = expectation(description: "load pending")
    let cancelled = expectation(description: "progress cancelled")
    let done = expectation(description: "cleanup completed")
    pending.onLoad = { loaded.fulfill() }
    pending.progress.cancellationHandler = { cancelled.fulfill() }
    let ownedInbox = inbox!
    let batch = ImportProviderBatch(limits: limits, makeInbox: { ownedInbox })
    batch.start([first, pending, third], progress: { _, _ in }, completion: { outcome in
      self.issue(.cancelled, outcome)
      XCTAssertTrue((try? ownedInbox.pending().isEmpty) == true)
      done.fulfill()
    })
    wait(for: [loaded], timeout: 5)
    batch.cancel()
    wait(for: [cancelled], timeout: 5)
    // Still owned until the materialization callback acknowledges cancellation.
    XCTAssertThrowsError(try inbox.pending()) { XCTAssertEqual($0 as? ImportIssue, .busy) }
    pending.deliver()
    wait(for: [done], timeout: 5)
    XCTAssertEqual(third.loadCount, 0)
  }
  func testCancelBeforeStartNeverLoads() throws {
    let p = try provider("first.txt")
    let done = expectation(description: "cancelled before start")
    let batch = ImportProviderBatch(limits: limits, makeInbox: { self.inbox })
    batch.cancel()
    batch.start([p], progress: { _, _ in }, completion: {
      self.issue(.cancelled, $0)
      done.fulfill()
    })
    wait(for: [done], timeout: 5)
    XCTAssertEqual(p.loadCount, 0)
  }
  func testExistingPendingRejectsShareBeforeLoading() throws {
    try inbox.stage(provider("old.txt").url!, cancellation: ImportCancellation()) { _ in }
    let before = try inbox.pending().map { $0["id"] as! String }
    let p = try provider("new.txt")
    issue(.busy, run([p]))
    XCTAssertEqual(p.loadCount, 0)
    XCTAssertEqual(try inbox.pending().map { $0["id"] as! String }, before)
  }
}
