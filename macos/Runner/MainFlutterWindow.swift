import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var services: MacServices?
  private let savedFrameName = NSWindow.FrameAutosaveName("ShioriMainWindow")
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let frame = self.frame
    contentViewController = controller
    setFrame(frame, display:true)
    minSize = NSSize(width:620,height:520)
    setContentSize(NSSize(width:1100,height:780))
    if !setFrameUsingName(savedFrameName) { center() }
    _ = setFrameAutosaveName(savedFrameName)
    fitToVisibleScreen()
    NotificationCenter.default.addObserver(self, selector:#selector(screenConfigurationChanged(_:)),
      name:NSApplication.didChangeScreenParametersNotification, object:nil)
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
