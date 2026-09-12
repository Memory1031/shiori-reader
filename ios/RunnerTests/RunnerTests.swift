import Foundation
import UIKit
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  private var directory: URL!
  private var inbox: ImportInbox!
  private let limits = ImportLimits(maxFiles: 4, maxFileBytes: 128 * 1024, maxBatchBytes: 256 * 1024)
  private let fm = FileManager.default
  override func setUpWithError() throws {
    directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    inbox = try ImportInbox(directory: directory.appendingPathComponent("inbox"), limits: limits)
  }
  override func tearDownWithError() throws { try fm.removeItem(at: directory) }
  private func input(_ name: String = "book.txt", bytes: Int = 3) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data(repeating: 65, count: bytes).write(to: url)
    return url
  }
  private func stage(_ urls: [URL]) throws {
    try inbox.stage(urls, cancellation: ImportCancellation()) { _ in }
  }
  private func issue(_ expected: ImportIssue, file: StaticString = #filePath, line: UInt = #line,
                     _ body: () throws -> Void) {
    XCTAssertThrowsError(try body(), file: file, line: line) {
      XCTAssertEqual($0 as? ImportIssue, expected, file: file, line: line)
    }
  }
  private func exists(_ name: String) -> Bool {
    fm.fileExists(atPath: inbox.root.appendingPathComponent(name).path)
  }
  private func unpublished(file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertFalse(exists("working"), file: file, line: line)
    XCTAssertFalse(exists("pending"), file: file, line: line)
    XCTAssertTrue(try inbox.pending().isEmpty, file: file, line: line)
  }
  private func session(_ count: Int = 3, cancellation: ImportCancellation = ImportCancellation()) throws -> ImportInbox.Session {
    try inbox.beginBatch(expectedCount: count, cancellation: cancellation)
  }
  private func ids() throws -> [String] { try inbox.pending().map { $0["id"] as! String } }
  private func itemDirectories() throws -> [URL] {
    try inbox.pending().map { URL(fileURLWithPath: $0["path"] as! String).deletingLastPathComponent() }
  }
  private func changeReceipt(_ index: Int = 0, _ edit: (inout [String: Any]) -> Void) throws {
    let url = try itemDirectories()[index].appendingPathComponent("receipt.json")
    var value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    edit(&value)
    try JSONSerialization.data(withJSONObject: value).write(to: url)
  }
  private func corrupted() throws {
    issue(.storage) { _ = try inbox.pending() }
    issue(.storage) { _ = try session(1) }
    issue(.storage) { try inbox.acknowledge("anything") }
    XCTAssertTrue(exists("pending"))
  }
  private func legacy() throws {
    let pending = inbox.root.appendingPathComponent("pending")
    try fm.createDirectory(at: pending, withIntermediateDirectories: false)
    try Data([65]).write(to: pending.appendingPathComponent("payload"))
    try JSONSerialization.data(withJSONObject: ["id": "legacy-id", "name": "legacy.txt", "size": 1])
      .write(to: pending.appendingPathComponent("receipt.json"))
  }

  func testProductionConstantsAndPickerMultiSelection() {
    XCTAssertEqual(ImportLimits.production.maxFiles, 64)
    XCTAssertEqual(ImportLimits.production.maxFileBytes, 128 * 1024 * 1024)
    XCTAssertEqual(ImportLimits.production.maxBatchBytes, 512 * 1024 * 1024)
    XCTAssertTrue(ImportBridge.makePicker().allowsMultipleSelection)
  }
  func testEmptyPending() throws { XCTAssertTrue(try inbox.pending().isEmpty) }
  func testSingleWrapperPublishesNewSchemaAndSurvivesSourceRemoval() throws {
    let url = try input()
    try inbox.stage(url, cancellation: ImportCancellation()) { _ in }
    try fm.removeItem(at: url)
    let reopened = try ImportInbox(directory: inbox.root, limits: limits)
    let receipts = try reopened.pending()
    XCTAssertEqual(receipts.count, 1)
    let path = try XCTUnwrap(receipts.first?["path"] as? String)
    XCTAssertTrue(path.contains("/pending/item-0000-"))
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data([65, 65, 65]))
  }
  func testThreeItemsPreserveInputOrderAndDuplicateNames() throws {
    let same = try input("同名.epub")
    try stage([same, input("a.txt"), same])
    XCTAssertEqual(try inbox.pending().map { $0["name"] as! String }, ["同名.epub", "a.txt", "同名.epub"])
    XCTAssertEqual(Set(try ids()).count, 3)
    XCTAssertEqual(try itemDirectories().map { String($0.lastPathComponent.prefix(10)) },
                   ["item-0000-", "item-0001-", "item-0002-"])
  }
  func testDisplayNameCannotDetermineDirectory() throws {
    let batch = try session(1)
    defer { try? batch.abort() }
    try batch.append(url: input(), displayName: "../../outside.txt")
    try batch.commit()
    XCTAssertEqual(try inbox.pending().first?["name"] as? String, "../../outside.txt")
    XCTAssertTrue(try itemDirectories()[0].path.hasPrefix(inbox.root.path + "/pending/item-0000-"))
  }
  func testProductionCount64AcceptedAnd65Rejected() throws {
    inbox = try ImportInbox(directory: inbox.root)
    let url = try input()
    issue(.batchLimit) { try stage(Array(repeating: url, count: 65)) }
    try unpublished()
    try stage(Array(repeating: url, count: 64))
    XCTAssertEqual(try inbox.pending().count, 64)
  }
  func testEmptyAndInjectedCountLimitsRejectBeforeWork() throws {
    issue(.unreadable) { try stage([]) }
    issue(.batchLimit) { _ = try session(5) }
    try unpublished()
  }
  func testActualPerFileLimitInAppend() throws {
    let batch = try session(1)
    defer { try? batch.abort() }
    issue(.tooLarge) { try batch.append(url: input(bytes: Int(limits.maxFileBytes) + 1)) }
    try unpublished()
  }
  func testActualBatchLimitAndExactBoundary() throws {
    let full = try input(bytes: Int(limits.maxFileBytes))
    issue(.batchLimit) { try stage([full, full, input("extra.txt", bytes: 1)]) }
    try unpublished()
    try stage([full, full])
    XCTAssertEqual(try inbox.pending().reduce(Int64(0)) { $0 + ($1["size"] as! NSNumber).int64Value }, limits.maxBatchBytes)
  }
  func testDeclaredSizeEarlyReject() throws {
    issue(.tooLarge) { try stage([input(bytes: Int(limits.maxFileBytes) + 1)]) }
    try unpublished()
  }
  func testLaterMetadataFailurePrecedesAnyRead() throws {
    // Reading the first source would fail unreadable. Later unsupported metadata
    // wins, proving the entire metadata pass precedes any payload read.
    issue(.unsupported) {
      try stage([directory.appendingPathComponent("missing.txt"), input("bad.pdf")])
    }
    try unpublished()
  }
  func testNonFileURLAndEmptyFileDoNotPublish() throws {
    issue(.unsupported) { try stage([URL(string: "https://invalid.example/book.txt")!]) }
    issue(.unreadable) { try stage([input(bytes: 0)]) }
    try unpublished()
  }
  func testSecondReadFailureRollsBackFirst() throws {
    issue(.unreadable) { try stage([input(), directory.appendingPathComponent("missing.txt")]) }
    try unpublished()
  }
  func testCancellationBeforeBegin() throws {
    let token = ImportCancellation()
    token.cancel()
    issue(.cancelled) { _ = try session(1, cancellation: token) }
    try unpublished()
  }
  func testSecondAppendCancellationRollsBackFirst() throws {
    let token = ImportCancellation()
    let batch = try session(3, cancellation: token)
    defer { try? batch.abort() }
    try batch.append(url: input())
    token.cancel()
    issue(.cancelled) { try batch.append(url: input("second.txt")) }
    try unpublished()
  }
  func testAbortAfterTwoOfThreeIsIdempotent() throws {
    let batch = try session()
    try batch.append(url: input())
    try batch.append(url: input())
    try batch.abort()
    try batch.abort()
    try unpublished()
  }
  func testIncompleteCommitAborts() throws {
    let batch = try session()
    try batch.append(url: input())
    issue(.storage) { try batch.commit() }
    try unpublished()
  }
  func testCommitOnceAndPostCommitAbortKeepsPending() throws {
    let batch = try session(1)
    try batch.append(url: input())
    try batch.commit()
    let before = try ids()
    issue(.storage) { try batch.commit() }
    try batch.abort()
    XCTAssertEqual(try ids(), before)
  }
  func testExtraAppendAborts() throws {
    let batch = try session(1)
    try batch.append(url: input())
    issue(.batchLimit) { try batch.append(url: input()) }
    try unpublished()
  }
  func testCancelImmediatelyBeforeCommit() throws {
    let token = ImportCancellation()
    let batch = try session(1, cancellation: token)
    try batch.append(url: input())
    token.cancel()
    issue(.cancelled) { try batch.commit() }
    try unpublished()
  }
  func testAckMiddleUnknownTwiceAndLast() throws {
    try stage([input(), input(), input()])
    let before = try ids()
    try inbox.acknowledge("../../outside")
    XCTAssertEqual(try ids(), before)
    try inbox.acknowledge(before[1])
    try inbox.acknowledge(before[1])
    XCTAssertEqual(try ids(), [before[0], before[2]])
    try inbox.acknowledge(before[0])
    try inbox.acknowledge(before[2])
    try unpublished()
  }
  func testLegacyReadBusyAndAck() throws {
    try legacy()
    XCTAssertEqual(try inbox.pending().first?["id"] as? String, "legacy-id")
    issue(.busy) { try stage([input()]) }
    try inbox.acknowledge("unknown")
    XCTAssertTrue(exists("pending/receipt.json"))
    try inbox.acknowledge("legacy-id")
    try inbox.acknowledge("legacy-id")
    try unpublished()
  }
  func testRecoveryOfWorkingTrashAndEmptyPending() throws {
    for name in ["working", "pending", "ack-trash-\(UUID().uuidString)"] {
      let url = inbox.root.appendingPathComponent(name)
      try fm.createDirectory(at: url, withIntermediateDirectories: false)
      if name != "pending" { try Data([1]).write(to: url.appendingPathComponent("partial")) }
    }
    try unpublishedAfterRecovery()
  }
  private func unpublishedAfterRecovery() throws {
    XCTAssertTrue(try inbox.pending().isEmpty)
    try unpublished()
    XCTAssertEqual(try fm.contentsOfDirectory(atPath: inbox.root.path), ["lock"])
  }
  func testAckTrashCrashRecoveryKeepsOtherReceipts() throws {
    try stage([input(), input(), input()])
    let before = try ids()
    let item = try itemDirectories()[1]
    let trash = inbox.root.appendingPathComponent("ack-trash-\(UUID().uuidString)")
    try fm.moveItem(at: item, to: trash)
    try fm.removeItem(at: trash.appendingPathComponent("receipt.json"))
    XCTAssertEqual(try ids(), [before[0], before[2]])
    XCTAssertFalse(fm.fileExists(atPath: trash.path))
  }
  func testMalformedJSONIsPreserved() throws {
    try stage([input()])
    let file = try itemDirectories()[0].appendingPathComponent("receipt.json")
    try Data("broken".utf8).write(to: file)
    try corrupted()
    XCTAssertEqual(try String(contentsOf: file), "broken")
  }
  func testMissingPayloadIsPreserved() throws {
    try stage([input()])
    try fm.removeItem(at: itemDirectories()[0].appendingPathComponent("payload"))
    try corrupted()
  }
  func testDuplicateIdRejected() throws {
    try stage([input(), input()])
    let first = try ids()[0]
    try changeReceipt(1) { $0["id"] = first }
    try corrupted()
  }
  func testDuplicateOrderRejected() throws {
    try stage([input(), input()])
    try changeReceipt(1) { $0["order"] = 0 }
    try corrupted()
  }
  func testFractionalAndBooleanMetadataRejected() throws {
    for size in [1.5, true, "3"] as [Any] {
      try stage([input()])
      try changeReceipt { $0["size"] = size }
      try corrupted()
      try fm.removeItem(at: inbox.root.appendingPathComponent("pending")) // Test fixture reset only.
    }
  }
  func testInvalidOrderAndSizeMismatchRejected() throws {
    try stage([input()])
    try changeReceipt { $0["order"] = -1 }
    try corrupted()
  }
  func testPayloadLengthMustMatchReceipt() throws {
    try stage([input()])
    try changeReceipt { $0["size"] = 2 }
    try corrupted()
  }
  func testUnexpectedPublishedChildRejected() throws {
    try stage([input()])
    try Data([1]).write(to: inbox.root.appendingPathComponent("pending/unexpected"))
    try corrupted()
  }
  func testPublishedSymlinkRejectedWithoutFollowingIt() throws {
    try stage([input()])
    let payload = try itemDirectories()[0].appendingPathComponent("payload")
    try fm.removeItem(at: payload)
    let outside = try input("outside.txt")
    try fm.createSymbolicLink(at: payload, withDestinationURL: outside)
    try corrupted()
    XCTAssertEqual(try Data(contentsOf: outside), Data([65, 65, 65]))
  }
  func testWorkingSymlinkCleanupOnlyUnlinks() throws {
    let outside = try input("outside.txt")
    try fm.createSymbolicLink(at: inbox.root.appendingPathComponent("working"), withDestinationURL: outside)
    XCTAssertTrue(try inbox.pending().isEmpty)
    XCTAssertTrue(fm.fileExists(atPath: outside.path))
  }
  func testCrossInstanceLockHeldUntilAbort() throws {
    let second = try ImportInbox(directory: inbox.root, limits: limits)
    let batch = try session()
    defer { try? batch.abort() }
    try batch.append(url: input())
    issue(.busy) { _ = try second.pending() }
    issue(.busy) { _ = try second.beginBatch(expectedCount: 1, cancellation: ImportCancellation()) }
    issue(.busy) { try second.acknowledge("none") }
    XCTAssertTrue(exists("working"))
    try batch.abort()
    XCTAssertTrue(try second.pending().isEmpty)
  }
  func testExistingBatchIsNeverOverwritten() throws {
    try stage([input(), input()])
    let before = try ids()
    issue(.busy) { try stage([input("new.txt")]) }
    XCTAssertEqual(try ids(), before)
  }
  func testOldAbortedSessionCannotRemoveNewWorking() throws {
    let old = try session(1)
    try old.abort()
    let current = try session(1)
    defer { try? current.abort() }
    try current.append(url: input())
    try old.abort()
    XCTAssertTrue(exists("working"))
    try current.commit()
    XCTAssertEqual(try inbox.pending().count, 1)
  }
  func testProgressIsMonotonicAndCancellationDuringCopyAborts() throws {
    inbox = try ImportInbox(directory: inbox.root,
      limits: ImportLimits(maxFiles: 3, maxFileBytes: 2 * 1024 * 1024, maxBatchBytes: 6 * 1024 * 1024))
    let url = try input(bytes: 2 * 1024 * 1024)
    var progress: [Int64] = []
    try inbox.stage([url, url, url], cancellation: ImportCancellation()) { progress.append($0) }
    XCTAssertEqual(progress, (1...6).map { Int64($0 * 1024 * 1024) })
    for id in try ids() { try inbox.acknowledge(id) }
    let token = ImportCancellation()
    issue(.cancelled) {
      try inbox.stage([url, url], cancellation: token) { _ in token.cancel() }
    }
    try unpublished()
  }
}
