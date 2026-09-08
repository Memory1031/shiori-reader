import XCTest

final class IntakeUITests: XCTestCase {
  func testShareHandoffAndPickerCancellation() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "dev.shiori.reader")
    let fixture = XCUIApplication()
    // Reset native presentation state, then clear the durable intake via UI.
    app.terminate()
    app.activate()
    if app.buttons["查看"].waitForExistence(timeout: 5) {
      app.buttons["查看"].tap()
    }
    if app.buttons["取消"].exists { app.buttons["取消"].tap() }
    for (button, file) in [
      ("Share TXT", "share-fixture.txt"), ("Share EPUB", "share-fixture.epub"),
    ] {
      app.terminate()
      fixture.launch()
      fixture.buttons[button].tap()
      let shiori = fixture.buttons["Shiori"]
      if !shiori.waitForExistence(timeout: 4) {
        let more = fixture.buttons.matching(NSPredicate(format: "label == '更多' OR label == 'More'"))
          .firstMatch
        if more.exists { more.tap() }
      }
      let target = fixture.descendants(matching: .any).matching(identifier: "Shiori").firstMatch
      XCTAssertTrue(target.waitForExistence(timeout: 5), fixture.debugDescription)
      target.tap()
      let saved = fixture.staticTexts["文件已保存。请打开 Shiori 确认导入。"]
      XCTAssertTrue(saved.waitForExistence(timeout: 10), fixture.debugDescription)
      fixture.buttons["完成"].tap()
      app.activate()
      XCTAssertTrue(app.staticTexts[file].waitForExistence(timeout: 10))
      app.buttons["查看"].tap()
      app.buttons["导入"].tap()
      XCTAssertTrue(
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS '暂不支持解析'")).firstMatch
          .waitForExistence(timeout: 5))
      app.buttons["取消"].tap()
    }
    app.buttons["导入书籍"].tap()
    app.buttons["选择文件"].tap()
    // A native document picker cancellation returns to the original import panel.
    XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    let cancel = app.navigationBars.buttons.matching(
      NSPredicate(format: "label == '取消' OR label == 'Cancel' OR label == '关闭'")
    )
    .firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
    cancel.tap()
    XCTAssertTrue(app.buttons["选择文件"].waitForExistence(timeout: 5))
  }
}
