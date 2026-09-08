import Flutter
import UIKit
import UniformTypeIdentifiers

final class ImportBridge: NSObject, FlutterStreamHandler, UIDocumentPickerDelegate {
  weak var host: UIViewController?
  private let worker = DispatchQueue(label: "dev.shiori.reader.import", qos: .userInitiated)
  private var sink: FlutterEventSink?
  private var pickerResult: FlutterResult?
  private var cancellation = ImportCancellation()
  private var copying = false
  private var deferredError: String?
  init(messenger: FlutterBinaryMessenger, host: UIViewController) {
    super.init()
    self.host = host
    FlutterMethodChannel(name: "dev.shiori.reader/import", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result)
      }
    FlutterEventChannel(name: "dev.shiori.reader/import_events", binaryMessenger: messenger)
      .setStreamHandler(self)
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    if let error = deferredError {
      events(["error": error])
      deferredError = nil
    }
    events([:])
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
  private func report(_ error: String) {
    if sink == nil { deferredError = error } else { sink?(["error": error]) }
  }
  func resumed() { sink?([:]) }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      guard pickerResult == nil && !copying else {
        result(FlutterError(code: "busy", message: nil, details: nil))
        return
      }
      pickerResult = result
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [.plainText, UTType(filenameExtension: "epub") ?? .data],
        asCopy: false)
      picker.allowsMultipleSelection = false
      picker.delegate = self
      var presenter = host
      while let next = presenter?.presentedViewController { presenter = next }
      presenter?.present(picker, animated: true)
    case "cancel":
      cancellation.cancel()
      if let pending = pickerResult, !copying {
        pickerResult = nil
        host?.dismiss(animated: true)
        pending(nil)
      }
      worker.async { DispatchQueue.main.async { result(nil) } }
    case "pending", "ack":
      worker.async {
        do {
          let inbox = try ImportInbox()
          let value: Any?
          if call.method == "pending" {
            value = try inbox.pending()
          } else {
            try inbox.acknowledge((call.arguments as? [String: Any])?["id"] as? String ?? "")
            value = nil
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: (error as? ImportIssue)?.rawValue ?? "storage", message: nil, details: nil))
          }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pickerResult
    pickerResult = nil
    result?(nil)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  {
    guard urls.count == 1 else {
      pickerResult?(FlutterError(code: "multiple", message: nil, details: nil))
      pickerResult = nil
      return
    }
    receive(urls[0], picked: true)
  }
  func receive(_ url: URL, picked: Bool = false) {
    guard !copying else {
      if picked {
        let result = pickerResult
        pickerResult = nil
        result?(FlutterError(code: "busy", message: nil, details: nil))
      } else {
        report("busy")
      }
      return
    }
    copying = true
    cancellation = ImportCancellation()
    let token = cancellation
    worker.async {
      var issue: String?
      do {
        try ImportInbox().stage(url, cancellation: token) { count in
          // Send bounded progress events, not every filesystem chunk.
          if count % (1024 * 1024) < 65536 {
            DispatchQueue.main.async { self.sink?(["bytes": count]) }
          }
        }
      } catch { issue = (error as? ImportIssue)?.rawValue ?? "unreadable" }
      DispatchQueue.main.async {
        self.copying = false
        if picked {
          let result = self.pickerResult
          self.pickerResult = nil
          result?(issue.map { FlutterError(code: $0, message: nil, details: nil) })
        } else if let issue = issue {
          self.report(issue)
        }
        self.sink?(["done": true])
      }
    }
  }
}
