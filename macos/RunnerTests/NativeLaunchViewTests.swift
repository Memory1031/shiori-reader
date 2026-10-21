import Cocoa

private final class ClickCounter: NSObject {
  var clicks = 0
  @objc func click(_ sender: NSButton) { clicks += 1 }
}

@main
struct NativeLaunchViewTests {
  static func main() {
    _ = NSApplication.shared
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 520))
    let counter = ClickCounter()
    let button = NSButton(frame: NSRect(x: 20, y: 20, width: 120, height: 40))
    button.target = counter
    button.action = #selector(ClickCounter.click(_:))
    content.addSubview(button)
    let point = NSPoint(x: 60, y: 40)

    // A successful notification removes immediately and cancels the deadline.
    let notified = NativeLaunchView(frame: content.bounds)
    content.addSubview(notified)
    notified.dismissAfterTimeout()
    notified.dismiss()
    notified.dismiss()
    assert(notified.superview == nil)
    assert(content.hitTest(point) === button)
    let retained = NSView(frame: content.bounds)
    retained.addSubview(notified)

    // No notification, or failure before native delivery: only the timer can exit.
    let missing = NativeLaunchView(frame: content.bounds)
    content.addSubview(missing)
    missing.dismissAfterTimeout()
    assert(content.hitTest(point) === missing, "The test must begin with a blocking cover")
    let start = Date()
    let deadline = start.addingTimeInterval(7)
    while missing.superview != nil && Date() < deadline {
      RunLoop.main.run(mode: .default, before: deadline)
    }
    assert(missing.superview == nil, "Missing notification left the interface covered")
    assert(Date().timeIntervalSince(start) >= 4.8, "The fallback removed the cover too early")
    assert(notified.superview === retained, "Successful dismissal did not cancel its timer")
    assert(content.hitTest(point) === button, "The underlying button is still blocked")
    (content.hitTest(point) as? NSButton)?.performClick(nil)
    assert(counter.clicks == 1)
    missing.dismiss() // A notification arriving after the deadline is harmless.
    assert(content.hitTest(point) === button)

    weak var released: NativeLaunchView?
    autoreleasepool {
      let closed = NativeLaunchView(frame: content.bounds)
      released = closed
      content.addSubview(closed)
      closed.dismissAfterTimeout()
      closed.removeFromSuperview()
    }
    assert(released == nil, "The fallback retained a closed cover")
    print("Native launch dismissal: notification, timeout, click and cleanup passed")
  }
}
