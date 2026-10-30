import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var services: MacServices?
  private var launchChannel: FlutterMethodChannel?
  private var readingChannel: FlutterMethodChannel?
  private var readingSleeping = false
  private let savedFrameName = NSWindow.FrameAutosaveName("ShioriMainWindow")
  override func awakeFromNib() {
    let launch = NativeLaunchView(frame: contentView?.bounds ?? .zero)
    launch.autoresizingMask = [.width, .height]
    backgroundColor = launch.paperColor
    contentView = launch
    minSize = NSSize(width:320,height:480)
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
    launch.dismissAfterTimeout()
    let channel = FlutterMethodChannel(name: "dev.shiori.reader/launch",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak launch] call, result in
      guard call.method == "firstFrame" else { result(FlutterMethodNotImplemented); return }
      launch?.dismiss()
      result(nil)
    }
    launchChannel = channel
    let reading = FlutterMethodChannel(name:"dev.shiori.reader/reading", binaryMessenger:controller.engine.binaryMessenger)
    reading.setMethodCallHandler { [weak self] call, result in
      guard call.method == "state" else { result(FlutterMethodNotImplemented); return }
      result(self?.readingState() ?? ["available":false,"wake":false])
    }
    readingChannel = reading
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                 NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification] {
      NotificationCenter.default.addObserver(self, selector:#selector(readingWindowChanged(_:)), name:name, object:self)
    }
    for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
      NotificationCenter.default.addObserver(self, selector:#selector(readingWindowChanged(_:)), name:name, object:nil)
    }
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
      NSWorkspace.shared.notificationCenter.addObserver(self, selector:#selector(readingPowerChanged(_:)), name:name, object:nil)
    }
    RegisterGeneratedPlugins(registry:controller)
    services = MacServices(controller:controller,window:self)
    registerForDraggedTypes([.fileURL])
    super.awakeFromNib()
  }
  deinit {
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    readingChannel?.setMethodCallHandler(nil)
  }
  private func readingState(wake: Bool = false) -> [String:Bool] {
    ["available":NSApp.isActive && isKeyWindow && !isMiniaturized && occlusionState.contains(.visible) && !readingSleeping,"wake":wake]
  }
  @objc private func readingWindowChanged(_ notification: Notification) {
    readingChannel?.invokeMethod("state",arguments:readingState())
  }
  @objc private func readingPowerChanged(_ notification: Notification) {
    let wake = notification.name == NSWorkspace.didWakeNotification
    readingSleeping = !wake
    readingChannel?.invokeMethod("state",arguments:readingState(wake:wake))
  }

  @objc private func screenConfigurationChanged(_ notification: Notification) { fitToVisibleScreen() }

  private func fitToVisibleScreen() {
    guard !styleMask.contains(.fullScreen), let target = NSScreen.screens.max(by: {
      let left = $0.visibleFrame.intersection(frame)
      let right = $1.visibleFrame.intersection(frame)
      return (left.isNull ? 0 : left.width * left.height) <
        (right.isNull ? 0 : right.width * right.height)
    }) else { return }
    let work = target.visibleFrame
    minSize = NSSize(width:min(320,work.width), height:min(480,work.height))
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
