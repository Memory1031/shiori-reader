import XCTest
import UIKit
@testable import ImportFixture

private final class ReceiverDouble: ImportBatchReceiving {
  var starts = 0
  var cancels = 0
  var progress: ((Int, Int) -> Void)?
  var completion: ((Result<ImportReceiptSummary, ImportIssue>) -> Void)?
  func start(_ providers: [ImportFileProvider], progress: @escaping (Int, Int) -> Void,
             completion: @escaping (Result<ImportReceiptSummary, ImportIssue>) -> Void) {
    starts += 1
    self.progress = progress
    self.completion = completion
  }
  func cancel() { cancels += 1 }
}

final class ShareViewTests: XCTestCase {
  private func drain() {
    let done = expectation(description: "main queue")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 2)
  }
  private func labels(_ view: UIView) -> [UILabel] {
    (view as? UILabel).map { [$0] } ?? view.subviews.flatMap(labels)
  }
  private func action(_ view: UIView) -> UIButton? {
    if let button = view as? UIButton { return button }
    return view.subviews.compactMap(action).first
  }
  func testCancellationWaitsForCleanupAndTerminatesExactlyOnce() {
    let receiver = ReceiverDouble()
    let controller = ShareViewController()
    controller.makeReceiver = { receiver }
    controller.inputProviders = []
    var completed = 0
    controller.requestCompletion = { completed += 1 }
    controller.loadViewIfNeeded()
    controller.viewDidAppear(false)
    controller.viewDidAppear(false)
    XCTAssertEqual(receiver.starts, 1)
    receiver.progress?(2, 3)
    drain()
    XCTAssertFalse(labels(controller.view).contains { $0.text?.contains("已收下") == true })
    controller.close()
    controller.close()
    XCTAssertEqual(receiver.cancels, 1)
    XCTAssertEqual(completed, 0)
    XCTAssertFalse(action(controller.view)!.isEnabled)
    receiver.completion?(.failure(.cancelled))
    drain()
    controller.close()
    receiver.completion?(.success(ImportReceiptSummary(names: ["late.txt"], pendingCount: 1)))
    drain()
    XCTAssertEqual(completed, 1)
    if case .terminated = controller.state {} else { XCTFail("Late callbacks changed terminated UI") }
  }
  func testPublishedSuccessWinsLateCancelAndDoneOnlyCloses() {
    let receiver = ReceiverDouble()
    let controller = ShareViewController()
    controller.makeReceiver = { receiver }
    controller.inputProviders = []
    var completed = 0
    controller.requestCompletion = { completed += 1 }
    controller.loadViewIfNeeded()
    controller.viewDidAppear(false)
    controller.close()
    receiver.completion?(.success(ImportReceiptSummary(names: ["合成短文.txt"], pendingCount: 7)))
    drain()
    if case .received(let summary) = controller.state {
      XCTAssertEqual(summary.names.count, 1)
      XCTAssertEqual(summary.pendingCount, 7)
    } else { XCTFail("Saved batch must be shown") }
    XCTAssertEqual(completed, 0)
    controller.close()
    controller.close()
    XCTAssertEqual(completed, 1)
  }
  func testCleanupFailureRemainsReadableUntilDone() {
    let receiver = ReceiverDouble()
    let controller = ShareViewController()
    controller.makeReceiver = { receiver }
    controller.inputProviders = []
    controller.loadViewIfNeeded()
    controller.viewDidAppear(false)
    controller.close()
    receiver.completion?(.failure(.storage))
    drain()
    if case .failed(.storage) = controller.state {} else { XCTFail("Cleanup failure hidden") }
    XCTAssertTrue(action(controller.view)!.isEnabled)
  }
  func testNativePreviewStatesAndSmallLargeTypeLayout() {
    let summary = ImportReceiptSummary(names: ["合成书籍第一卷.epub", "Synthetic Second Volume.epub", "合成短文.txt"], pendingCount: 7)
    let scenes: [(String, ShareViewController.State, UIUserInterfaceStyle)] = [
      ("received-light", .received(summary), .light),
      ("received-dark", .received(summary), .dark),
      ("receiving", .receiving(index: 2, count: 3), .light),
      ("inbox-full", .failed(.inboxFull), .light),
      ("cancelling", .cancelling, .dark),
    ]
    for (name, state, style) in scenes {
      let controller = ShareViewController()
      let receiver = ReceiverDouble()
      controller.makeReceiver = { receiver }
      controller.inputProviders = summary.names.map { name in
        let provider = NSItemProvider()
        provider.suggestedName = name
        return provider
      }
      controller.loadViewIfNeeded()
      controller.viewDidAppear(false)
      controller.display(state)
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
      window.overrideUserInterfaceStyle = style
      window.rootViewController = controller
      window.makeKeyAndVisible()
      controller.view.layoutIfNeeded()
      let button = action(controller.view)!
      XCTAssertTrue(controller.view.bounds.contains(button.frame), name)
      XCTAssertGreaterThanOrEqual(button.bounds.height, 50)
      XCTAssertTrue(labels(controller.view).contains { $0.accessibilityTraits.contains(.header) })
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
      let attachment = XCTAttachment(image: image)
      attachment.name = "native-preview-" + name
      attachment.lifetime = .keepAlways
      add(attachment)
      window.isHidden = true
    }
    let parent = UIViewController()
    let controller = ShareViewController()
    controller.display(.received(ImportReceiptSummary(names: (1...64).map { "合成很长的文件名-\($0).epub" }, pendingCount: 64)))
    parent.addChild(controller)
    parent.view.addSubview(controller.view)
    parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
    controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 350)
    controller.view.layoutIfNeeded()
    XCTAssertTrue(controller.view.bounds.contains(action(controller.view)!.frame))
    XCTAssertEqual(labels(controller.view).filter { $0.text?.hasPrefix("合成很长") == true }.count, 4)
    XCTAssertTrue(labels(controller.view).contains { $0.accessibilityLabel?.contains("64.epub") == true })
  }
}
