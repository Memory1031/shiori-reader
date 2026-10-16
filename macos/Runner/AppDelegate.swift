import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if let services = MacServices.shared { services.accept(filenames) }
    else { MacServices.pendingFiles.append(contentsOf:filenames.prefix(max(0,65 - MacServices.pendingFiles.count))) }
    sender.reply(toOpenOrPrint:.success)
  }
}
