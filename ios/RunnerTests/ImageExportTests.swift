import Flutter
import Photos
import UIKit
import XCTest
@testable import Runner

private final class ExportMessenger: NSObject, FlutterBinaryMessenger {
  var handler: FlutterBinaryMessageHandler?
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
  func invoke(_ method: String, _ args: [String: Any], reply: @escaping (String?) -> Void) {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: args))) { data in
      reply(data.flatMap { codec.decodeEnvelope($0) as? String })
    }
  }
}

private final class ExportHost: UIViewController {
  var presented: ((UIDocumentPickerViewController) -> Void)?
  override func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
    presented?(viewControllerToPresent as! UIDocumentPickerViewController)
    completion?()
  }
}

final class ImageExportTests: XCTestCase {
  private var root: URL!
  private var file: URL!
  private var messenger: ExportMessenger!
  private var bridge: ImageExportBridge!
  private var host: UIViewController!
  private var bytes = Data([137,80,78,71,13,10,26,10,1,2,3])
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    let folder = root.appendingPathComponent("shiori-image-export/export-test")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    file = folder.appendingPathComponent("shiori-0123456789ab-123.png")
    try bytes.write(to: file)
    messenger = ExportMessenger()
    host = UIViewController()
  }
  override func tearDownWithError() throws {
    bridge = nil
    try FileManager.default.removeItem(at: root)
  }
  private var args: [String: Any] {
    ["id": file.lastPathComponent, "name": file.lastPathComponent,
     "path": file.path, "size": bytes.count, "mime": "image/png", "asFile": false]
  }
  private func start(_ photos: ImageExportPhotos) {
    bridge = ImageExportBridge(messenger: messenger, host: host, photos: photos, temporary: root)
  }
  func testStagingBoundaryAndOriginalFormat() throws {
    XCTAssertEqual(try ImageExportBridge.validate(args, temporary: root), file)
    var invalid = args
    invalid["mime"] = "image/jpeg"
    XCTAssertThrowsError(try ImageExportBridge.validate(invalid, temporary: root))
    invalid = args; invalid["size"] = 1
    XCTAssertThrowsError(try ImageExportBridge.validate(invalid, temporary: root))
    invalid = args; invalid["path"] = root.appendingPathComponent(file.lastPathComponent).path
    XCTAssertThrowsError(try ImageExportBridge.validate(invalid, temporary: root))
    let original = root.appendingPathComponent("outside.png")
    try bytes.write(to: original)
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: original)
    XCTAssertThrowsError(try ImageExportBridge.validate(args, temporary: root))
    XCTAssertEqual(try Data(contentsOf: original), bytes)
  }
  func testDeniedDoesNotRequestAgainOrSubmitPhoto() {
    start(ImageExportPhotos(status: { .denied }, authorize: { _ in XCTFail() }, add: { _, _ in XCTFail() }))
    let done = expectation(description: "denied")
    messenger.invoke("save", args) { value in XCTAssertEqual(value, "permissionDenied"); done.fulfill() }
    wait(for: [done], timeout: 3)
  }
  func testCloseDuringPermissionWaitPreventsPhotoWriteAndRepliesOnce() {
    let permission = expectation(description: "permission requested")
    var authorize: ((PHAuthorizationStatus) -> Void)?
    start(ImageExportPhotos(status: { .notDetermined }, authorize: { authorize = $0; permission.fulfill() },
                            add: { _, _ in XCTFail() }))
    let done = expectation(description: "cancelled")
    messenger.invoke("save", args) { value in XCTAssertEqual(value, "cancelled"); done.fulfill() }
    wait(for: [permission], timeout: 3)
    messenger.invoke("cancel", args) { _ in }
    authorize?(.authorized)
    wait(for: [done], timeout: 3)
  }
  func testPhotoCompletionOwnsResultEvenAfterCloseAndRejectsSecondFlight() {
    let submitted = expectation(description: "submitted")
    var complete: ((Bool, Error?) -> Void)?
    start(ImageExportPhotos(status: { .authorized }, authorize: { _ in XCTFail() }, add: { file, callback in
      XCTAssertEqual(try? Data(contentsOf: file), self.bytes)
      complete = callback
      submitted.fulfill()
    }))
    let saved = expectation(description: "saved after true completion")
    var replies = 0
    messenger.invoke("save", args) { value in replies += 1; XCTAssertEqual(value, "savedPhotos"); saved.fulfill() }
    wait(for: [submitted], timeout: 3)
    messenger.invoke("save", args) { XCTAssertEqual($0, "unavailable") }
    messenger.invoke("cancel", args) { _ in }
    XCTAssertEqual(replies, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    complete?(true, nil)
    wait(for: [saved], timeout: 3)
    XCTAssertEqual(replies, 1)
  }
  func testDocumentPickerCancellationRepliesOnceWithoutConsumingOriginal() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
    let presenter = ExportHost()
    window.rootViewController = presenter
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host = presenter
    start(ImageExportPhotos(status: { XCTFail(); return .denied },
                            authorize: { _ in XCTFail() }, add: { _, _ in XCTFail() }))
    let presented = expectation(description: "file picker only on explicit asFile")
    var picker: UIDocumentPickerViewController?
    presenter.presented = { picker = $0; presented.fulfill() }
    var fileArgs = args
    fileArgs["asFile"] = true
    let done = expectation(description: "cancelled exactly once")
    var replies = 0
    messenger.invoke("save", fileArgs) { value in
      replies += 1
      XCTAssertEqual(value, "cancelled")
      done.fulfill()
    }
    wait(for: [presented], timeout: 3)
    XCTAssertEqual(picker?.documentPickerMode, .exportToService)
    messenger.invoke("cancel", args) { _ in }
    XCTAssertEqual(replies, 0) // Route close cannot release the picker's file.
    bridge.documentPickerWasCancelled(picker!)
    bridge.documentPickerWasCancelled(picker!)
    wait(for: [done], timeout: 3)
    XCTAssertEqual(replies, 1)
    XCTAssertEqual(try? Data(contentsOf: file), bytes)
  }
  func testUnsupportedResourceIsDistinctFromStorageFailure() {
    for (error, expected) in [
      (NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.invalidResource.rawValue), "unsupportedFormat"),
      (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError), "storageFailure")
    ] {
      start(ImageExportPhotos(status: { .authorized }, authorize: { _ in XCTFail() }, add: { _, reply in reply(false, error) }))
      let done = expectation(description: expected)
      messenger.invoke("save", args) { XCTAssertEqual($0, expected); done.fulfill() }
      wait(for: [done], timeout: 3)
    }
  }
}
