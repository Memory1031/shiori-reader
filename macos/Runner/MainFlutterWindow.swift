import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var services: MacServices?
  override func awakeFromNib() {
    let controller = FlutterViewController()
    let frame = self.frame
    contentViewController = controller
    setFrame(frame, display:true)
    minSize = NSSize(width:620,height:520)
    setContentSize(NSSize(width:1100,height:780))
    center()
    RegisterGeneratedPlugins(registry:controller)
    services = MacServices(controller:controller,window:self)
    registerForDraggedTypes([.fileURL])
    super.awakeFromNib()
  }
  @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { return false }
    services?.accept(urls.map(\.path)); return true
  }
}
