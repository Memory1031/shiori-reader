import Cocoa

/// Same paper and rounded logo as the other native runners, without a wordmark.
final class NativeLaunchView: NSView {
  private var dismissalTimer: Timer?

  func dismissAfterTimeout() {
    dismissalTimer?.invalidate()
    // Alternate Dart entry points and failed notifications must not leave a cover.
    let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in self?.dismiss() }
    dismissalTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func dismiss() {
    dismissalTimer?.invalidate()
    dismissalTimer = nil
    removeFromSuperview()
  }

  deinit { dismissalTimer?.invalidate() }

  private let logo = NSImage(named: "AppIcon")
  private var dark: Bool {
    effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }
  var paperColor: NSColor {
    dark ? NSColor(srgbRed: 27/255, green: 24/255, blue: 28/255, alpha: 1)
      : NSColor(srgbRed: 250/255, green: 248/255, blue: 244/255, alpha: 1)
  }
  override var isOpaque: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    paperColor.setFill()
    bounds.fill()
    let scale = min(1, min(bounds.width / 240, bounds.height / 356))
    // Align with the logo above Flutter LaunchView's title and loading status.
    let image = NSRect(x: bounds.midX - 64 * scale,
      y: bounds.midY + 10 * scale, width: 128 * scale, height: 128 * scale)
    let frame = NSBezierPath(roundedRect: image.insetBy(dx: -6 * scale, dy: -6 * scale),
      xRadius: 30 * scale, yRadius: 30 * scale)
    let surface = dark ? NSColor(srgbRed: 37/255, green: 33/255, blue: 38/255, alpha: 1)
      : NSColor(srgbRed: 255/255, green: 252/255, blue: 248/255, alpha: 1)
    let line = dark ? NSColor(srgbRed: 69/255, green: 64/255, blue: 71/255, alpha: 0.5)
      : NSColor(srgbRed: 222/255, green: 216/255, blue: 213/255, alpha: 0.5)
    surface.setFill()
    frame.fill()
    line.setStroke()
    frame.lineWidth = 1
    frame.stroke()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: image, xRadius: 24 * scale, yRadius: 24 * scale).addClip()
    logo?.draw(in: image, from: .zero, operation: .sourceOver, fraction: 1,
      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
  }
}
