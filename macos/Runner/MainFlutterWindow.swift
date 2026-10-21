import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var services: MacServices?
  private var launchChannel: FlutterMethodChannel?
  private let savedFrameName = NSWindow.FrameAutosaveName("ShioriMainWindow")
  override func awakeFromNib() {
    let launch = NativeLaunchView(frame: contentView?.bounds ?? .zero)
    launch.autoresizingMask = [.width, .height]
    backgroundColor = launch.paperColor
    contentView = launch
    minSize = NSSize(width:620,height:520)
    setContentSize(NSSize(width:1280,height:900))
    if !setFrameUsingName(savedFrameName) { center() }
    _ = setFrameAutosaveName(savedFrameName)
    fitToVisibleScreen()
    NotificationCenter.default.addObserver(self, selector:#selector(screenConfigurationChanged(_:)),
      name:NSApplication.didChangeScreenParametersNotification, object:nil)
    // Paint the native cover before synchronous engine and plugin setup.
    makeKeyAndOrderFront(nil)
    displayIfNeeded()
    let controller = FlutterViewController()
    controller.backgroundColor = launch.paperColor
    let frame = self.frame
    contentViewController = controller
    setFrame(frame, display:true)
    launch.frame = controller.view.bounds
    controller.view.addSubview(launch)
    let channel = FlutterMethodChannel(name: "dev.shiori.reader/launch",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak launch] call, result in
      guard call.method == "firstFrame" else { result(FlutterMethodNotImplemented); return }
      launch?.removeFromSuperview()
      result(nil)
    }
    launchChannel = channel
    RegisterGeneratedPlugins(registry:controller)
    services = MacServices(controller:controller,window:self)
    registerForDraggedTypes([.fileURL])
    super.awakeFromNib()
  }
  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func screenConfigurationChanged(_ notification: Notification) { fitToVisibleScreen() }

  private func fitToVisibleScreen() {
    guard !styleMask.contains(.fullScreen), let target = NSScreen.screens.max(by: {
      let left = $0.visibleFrame.intersection(frame)
      let right = $1.visibleFrame.intersection(frame)
      return (left.isNull ? 0 : left.width * left.height) <
        (right.isNull ? 0 : right.width * right.height)
    }) else { return }
    let work = target.visibleFrame
    minSize = NSSize(width:min(620,work.width), height:min(520,work.height))
    var fitted = frame
    fitted.size.width = min(max(fitted.width,minSize.width),work.width)
    fitted.size.height = min(max(fitted.height,minSize.height),work.height)
    fitted.origin.x = min(max(fitted.minX,work.minX),work.maxX - fitted.width)
    fitted.origin.y = min(max(fitted.minY,work.minY),work.maxY - fitted.height)
    if fitted != frame { setFrame(fitted, display:true) }
  }
  @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { return false }
    services?.accept(urls.map(\.path)); return true
  }
}

/// Same paper and rounded logo as the other native runners, without a wordmark.
private final class NativeLaunchView: NSView {
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
