import Foundation
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  private var directory: URL!
  private var inbox: ImportInbox!
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    inbox = try ImportInbox(directory: directory.appendingPathComponent("inbox"))
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
  private func input(_ name: String = "book.txt", text: String = "offline book") throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data(text.utf8).write(to: url)
    return url
  }
  func testOwnedCopySurvivesOriginalRemovalAndReopen() throws {
    let url = try input()
    try inbox.stage(url, cancellation: ImportCancellation()) { _ in }
    try FileManager.default.removeItem(at: url)
    let reopened = try ImportInbox(directory: directory.appendingPathComponent("inbox"))
    let receipt = try XCTUnwrap(reopened.pending())
    let path = try XCTUnwrap(receipt["path"] as? String)
    XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "offline book")
    try reopened.acknowledge("stale-id")
    XCTAssertNotNil(try reopened.pending())
    try reopened.acknowledge(receipt["id"] as! String)
    try reopened.acknowledge(receipt["id"] as! String)
    XCTAssertNil(try reopened.pending())
  }
  func testPendingReceiptIsNotOverwritten() throws {
    try inbox.stage(input(), cancellation: ImportCancellation()) { _ in }
    XCTAssertThrowsError(
      try inbox.stage(input("second.txt"), cancellation: ImportCancellation()) { _ in }
    ) {
      XCTAssertEqual(($0 as? ImportIssue)?.rawValue, "busy")
    }
    XCTAssertEqual(try inbox.pending()?["name"] as? String, "book.txt")
  }
  func testCancellationRemovesPartialCopy() throws {
    let cancel = ImportCancellation()
    cancel.cancel()
    XCTAssertThrowsError(try inbox.stage(input(), cancellation: cancel) { _ in }) {
      XCTAssertEqual(($0 as? ImportIssue)?.rawValue, "cancelled")
    }
    XCTAssertNil(try inbox.pending())
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: inbox.root.appendingPathComponent("working").path))
  }
  func testStaleWorkingCopyRecovery() throws {
    let work = inbox.root.appendingPathComponent("working")
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    try Data([1, 2]).write(to: work.appendingPathComponent("payload"))
    XCTAssertNil(try inbox.pending())
    XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
  }
  func testTypeAndMissingSourceFailuresDoNotPublish() throws {
    XCTAssertThrowsError(
      try inbox.stage(input("bad.pdf"), cancellation: ImportCancellation()) { _ in }
    ) {
      XCTAssertEqual(($0 as? ImportIssue)?.rawValue, "unsupported")
    }
    XCTAssertThrowsError(
      try inbox.stage(
        directory.appendingPathComponent("missing.txt"), cancellation: ImportCancellation()
      ) { _ in })
    XCTAssertNil(try inbox.pending())
  }
  func testActualBytesLimitAndRetry() throws {
    let url = try input()
    let file = try FileHandle(forWritingTo: url)
    try file.truncate(atOffset: UInt64(ImportInbox.maxBytes + 1))
    try file.close()
    XCTAssertThrowsError(try inbox.stage(url, cancellation: ImportCancellation()) { _ in }) {
      XCTAssertEqual(($0 as? ImportIssue)?.rawValue, "tooLarge")
    }
    XCTAssertNil(try inbox.pending())
    try inbox.stage(
      input("retry.epub", text: "PK\u{3}\u{4}fixture"), cancellation: ImportCancellation()
    ) { _ in }
    XCTAssertNotNil(try inbox.pending())
  }
  func testCrossOwnerLockDoesNotDeleteInFlightCopy() throws {
    let second = try ImportInbox(directory: inbox.root)
    let started = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let done = expectation(description: "copy")
    let url = try input()
    DispatchQueue.global().async {
      defer { done.fulfill() }
      do {
        try self.inbox.stage(url, cancellation: ImportCancellation()) { _ in
          started.signal()
          _ = resume.wait(timeout: .now() + 5)
        }
      } catch { XCTFail("copy failed: \(error)") }
    }
    XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
    XCTAssertThrowsError(try second.pending()) {
      XCTAssertEqual(($0 as? ImportIssue)?.rawValue, "busy")
    }
    resume.signal()
    wait(for: [done], timeout: 5)
    XCTAssertNotNil(try second.pending())
  }
}
