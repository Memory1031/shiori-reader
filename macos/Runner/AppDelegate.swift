import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static func main() {
    guard let lease = try? acquireInstallationLease(Bundle.main.bundleURL) else { return }
    defer { close(lease) }
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  override func application(_ sender: NSApplication, open urls: [URL]) {
    let files = urls.filter { $0.isFileURL && ["txt", "epub"].contains($0.pathExtension.lowercased()) }
    if !files.isEmpty {
      if let services = MacServices.shared { services.accept(files.map(\.path)) }
      else { MacServices.pendingFiles.append(contentsOf:files.prefix(max(0,65 - MacServices.pendingFiles.count)).map(\.path)) }
    }
    let remaining = urls.filter { !files.contains($0) }
    if !remaining.isEmpty { super.application(sender, open:remaining) }
  }
}
