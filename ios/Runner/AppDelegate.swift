import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var importBridge: ImportBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      importBridge = ImportBridge(messenger: controller.binaryMessenger, host: controller)
      if let url = launchOptions?[.url] as? URL { importBridge?.receive(url) }
    }
    return launched
  }
  override func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.isFileURL {
      importBridge?.receive(url)
      return true
    }
    return super.application(app, open: url, options: options)
  }
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    importBridge?.resumed()
  }
}
