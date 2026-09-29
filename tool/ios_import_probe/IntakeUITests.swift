import XCTest

/// Synthetic host -> real system ShareExtension -> production Runner on a simulator.
final class IntakeUITests: XCTestCase {
  func testContinuousShareThenOneConfirmation() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "dev.shiori.reader")
    let fixture = XCUIApplication()
    // This probe is for an isolated simulator. Clean only the three synthetic
    // receipts left by an interrupted run, through the application's own UI.
    app.activate()
    let previousReview = app.buttons.matching(NSPredicate(format: "label == '查看' OR label == 'Review'")).firstMatch
    if previousReview.waitForExistence(timeout: 3) { previousReview.tap() }
    let synthetic = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'synthetic-share-'"))
    if synthetic.count > 0 {
      XCTAssertEqual(synthetic.count, 3)
      let prepared = app.staticTexts.matching(NSPredicate(format: "label == '准备导入 3 本书' OR label == 'Ready to import 3 books'")).firstMatch
      if prepared.exists {
        app.buttons.matching(NSPredicate(format: "label == '取消' OR label == 'Cancel'")).firstMatch.tap()
      } else {
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == '已导入 3 本书' OR label == 'Imported 3 books'")).firstMatch.exists,
                      "Refuse to discard an unexpected inbox")
        app.buttons.matching(NSPredicate(format: "label == '完成' OR label == 'Done'")).firstMatch.tap()
      }
    }
    app.terminate()
    fixture.launch()
    for index in 1...3 {
      fixture.buttons["Share TXT"].tap()
      let target = fixture.descendants(matching: .any).matching(identifier: "Shiori").firstMatch
      if !target.waitForExistence(timeout: 5) {
        let more = fixture.buttons.matching(NSPredicate(format: "label == '更多' OR label == 'More'" )).firstMatch
        if more.exists { more.tap() }
      }
      XCTAssertTrue(target.waitForExistence(timeout: 5), fixture.debugDescription)
      target.tap()
      let received = fixture.staticTexts.matching(NSPredicate(format: "label CONTAINS '已收下 1' OR label CONTAINS '1 file received'")).firstMatch
      XCTAssertTrue(received.waitForExistence(timeout: 15), fixture.debugDescription)
      let total = fixture.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "共有 \(index) 个", "\(index) file")).firstMatch
      XCTAssertTrue(total.exists, fixture.debugDescription)
      if index == 3 {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "system-share-extension-third-receive"
        screenshot.lifetime = .keepAlways
        add(screenshot)
      }
      fixture.buttons["share-action"].tap()
      XCTAssertTrue(fixture.buttons["Share TXT"].waitForExistence(timeout: 5))
      XCTAssertNotEqual(app.state, .runningForeground)
    }
    app.activate()
    let pending = app.staticTexts.matching(NSPredicate(format: "label == '3 个文件待导入' OR label == '3 files awaiting import'")).firstMatch
    XCTAssertTrue(pending.waitForExistence(timeout: 15), app.debugDescription)
    let review = app.buttons.matching(NSPredicate(format: "label == '查看' OR label == 'Review'")).firstMatch
    review.tap()
    let importAll = app.buttons.matching(NSPredicate(format: "label == '导入全部' OR label == 'Import all'")).firstMatch
    XCTAssertTrue(importAll.waitForExistence(timeout: 5), app.debugDescription)
    importAll.tap()
    let success = app.staticTexts.matching(NSPredicate(format: "label == '已导入 3 本书' OR label == 'Imported 3 books'")).firstMatch
    XCTAssertTrue(success.waitForExistence(timeout: 20), app.debugDescription)
  }
  func testMultipleAttachmentsAfterSuccessAndPickerCancellation() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "dev.shiori.reader")
    let fixture = XCUIApplication()
    fixture.launch()
    fixture.buttons["Share multiple"].tap()
    let shiori = fixture.descendants(matching: .any).matching(identifier: "Shiori").firstMatch
    XCTAssertTrue(shiori.waitForExistence(timeout: 5), fixture.debugDescription)
    shiori.tap()
    let received = fixture.staticTexts.matching(NSPredicate(format: "label CONTAINS '已收下 2' OR label CONTAINS '2 files received'")).firstMatch
    XCTAssertTrue(received.waitForExistence(timeout: 15), fixture.debugDescription)
    fixture.buttons["share-action"].tap()
    app.activate()
    let review = app.buttons.matching(NSPredicate(format: "label == '查看' OR label == 'Review'")).firstMatch
    if review.waitForExistence(timeout: 3) { review.tap() }
    let ready = app.staticTexts.matching(NSPredicate(format: "label == '准备导入 2 本书' OR label == 'Ready to import 2 books'")).firstMatch
    XCTAssertTrue(ready.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'share-fixture.epub'")).firstMatch.exists)
    app.buttons.matching(NSPredicate(format: "label == '取消' OR label == 'Cancel'")).firstMatch.tap()
    app.buttons.matching(NSPredicate(format: "label == '更多' OR label == 'More'")).firstMatch.tap()
    let importEntry = app.buttons.matching(NSPredicate(format: "label == '导入书籍' OR label == 'Import book'")).firstMatch
    XCTAssertTrue(importEntry.waitForExistence(timeout: 5), app.debugDescription)
    importEntry.tap()
    app.buttons.matching(NSPredicate(format: "label == '选择文件' OR label == 'Choose file'")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    let cancel = app.navigationBars.buttons.matching(NSPredicate(format: "label == '取消' OR label == 'Cancel' OR label == '关闭'")).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
    cancel.tap()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == '选择文件' OR label == 'Choose file'")).firstMatch.waitForExistence(timeout: 5))
  }

}
