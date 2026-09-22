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
      FlutterMethodChannel(name: "dev.shiori.reader/app", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "info" {
            result([
              "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
              "build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            ])
          } else if call.method == "openRelease" {
            guard let value = call.arguments as? String,
              let url = URL(string: value),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "github.com",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              (parts.path == "/Memory1031/shiori-reader" ||
                parts.path.hasPrefix("/Memory1031/shiori-reader/releases/"))
            else {
              result(false)
              return
            }
            UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
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
