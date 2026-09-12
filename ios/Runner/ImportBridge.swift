import Flutter
import UIKit
import UniformTypeIdentifiers

final class ImportBridge: NSObject, FlutterStreamHandler, UIDocumentPickerDelegate {
  weak var host: UIViewController?
  private let worker = DispatchQueue(label: "dev.shiori.reader.import", qos: .userInitiated)
  private var sink: FlutterEventSink?
  private var pickerResult: FlutterResult?
  private var pickerRequest: UUID?
  private weak var activePicker: UIDocumentPickerViewController?
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
      let request = UUID()
      pickerRequest = request
      worker.async {
        var issue: ImportIssue?
        do { if try !ImportInbox().pending().isEmpty { issue = .busy } }
        catch { issue = (error as? ImportIssue) ?? .storage }
        DispatchQueue.main.async {
          guard self.pickerRequest == request else { return }
          if let issue = issue {
            self.completePicker(issue.rawValue)
            return
          }
          let picker = Self.makePicker()
          picker.delegate = self
          self.activePicker = picker
          var presenter = self.host
          while let next = presenter?.presentedViewController { presenter = next }
          guard let presenter = presenter else {
            self.completePicker("unreadable")
            return
          }
          presenter.present(picker, animated: true)
        }
      }
    case "cancel":
      cancellation.cancel()
      if let pending = pickerResult, !copying {
        pickerResult = nil
        pickerRequest = nil
        activePicker = nil
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
    guard controller === activePicker else { return }
    completePicker(nil)
  }
  static func makePicker() -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.plainText, UTType(filenameExtension: "epub") ?? .data], asCopy: false)
    picker.allowsMultipleSelection = true
    return picker
  }
  private func completePicker(_ issue: String?) {
    let result = pickerResult
    pickerResult = nil
    pickerRequest = nil
    activePicker = nil
    result?(issue.map { FlutterError(code: $0, message: nil, details: nil) })
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  {
    guard controller === activePicker, pickerResult != nil else { return }
    activePicker = nil
    receive(urls, picked: true)
  }
  func receive(_ url: URL, picked: Bool = false) {
    receive([url], picked: picked)
  }
  private func receive(_ urls: [URL], picked: Bool) {
    guard !copying && (picked || pickerResult == nil) else {
      if picked {
        let result = pickerResult
        pickerResult = nil
        pickerRequest = nil
        result?(FlutterError(code: "busy", message: nil, details: nil))
      } else {
        report("busy")
      }
      return
    }
    do { try ImportLimits.production.checkCount(urls.count) }
    catch {
      let issue = (error as? ImportIssue)?.rawValue ?? "unreadable"
      if picked { completePicker(issue) } else { report(issue) }
      return
    }
    copying = true
    cancellation = ImportCancellation()
    let token = cancellation
    sink?(["bytes": 0])
    worker.async {
      var issue: String?
      do {
        try ImportInbox().stage(urls, cancellation: token) { count in
          DispatchQueue.main.async { self.sink?(["bytes": count]) }
        }
      } catch { issue = (error as? ImportIssue)?.rawValue ?? "unreadable" }
      DispatchQueue.main.async {
        self.copying = false
        if picked {
          self.completePicker(issue)
        } else if let issue = issue {
          self.report(issue)
        }
        self.sink?(["done": true])
      }
    }
  }
}
