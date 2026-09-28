import Flutter
import UIKit
import Photos

/// PhotoKit boundary; injectable to verify permission and completion ordering.
struct ImageExportPhotos {
  var status: () -> PHAuthorizationStatus
  var authorize: (@escaping (PHAuthorizationStatus) -> Void) -> Void
  var add: (URL, @escaping (Bool, Error?) -> Void) -> Void
  static let live = ImageExportPhotos(
    status: { PHPhotoLibrary.authorizationStatus(for: .addOnly) },
    authorize: { PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: $0) },
    add: { file, completion in
      PHPhotoLibrary.shared().performChanges({
        let asset = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = file.lastPathComponent
        options.shouldMoveFile = false
        asset.addResource(with: .photo, fileURL: file, options: options)
      }, completionHandler: completion)
    })
}

/// Retained by AppDelegate. Each request keeps its staging file borrowed until
/// Photos or the document picker has finished consuming it.
final class ImageExportBridge: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private weak var host: UIViewController?
  private let photoLibrary: ImageExportPhotos
  private let temporary: URL
  private let channel: FlutterMethodChannel
  private let worker = DispatchQueue(label: "dev.shiori.reader.image-export")
  private var pending: Request?
  private class Request {
    let id: String
    let result: FlutterResult
    var cancelled = false
    var file: URL?
    var picker: UIDocumentPickerViewController?
    init(id: String, result: @escaping FlutterResult) { self.id = id; self.result = result }
  }
  init(messenger: FlutterBinaryMessenger, host: UIViewController,
       photos: ImageExportPhotos = .live,
       temporary: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) {
    self.host = host
    self.photoLibrary = photos
    self.temporary = temporary
    channel = FlutterMethodChannel(name: "dev.shiori.reader/image_export", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result("unavailable"); return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "cancel":
        if let request = self.pending, request.id == args?["id"] as? String {
          request.cancelled = true
          // Photos and the export picker may already be consuming staging.
          // Their genuine completion/cancel delegate owns the reply; do not
          // dismiss and free their input early when the Flutter route closes.
        }
        result(nil)
      case "save":
        guard self.pending == nil else { result("unavailable"); return }
        let request = Request(id: args?["id"] as? String ?? "", result: result)
        self.pending = request
        self.worker.async {
          do {
            let file = try Self.validate(args, temporary: self.temporary)
            DispatchQueue.main.async {
              guard !request.cancelled else { self.finish(request, "cancelled"); return }
              request.file = file
              if args?["asFile"] as? Bool == true { self.pick(request) }
              else { self.photos(request) }
            }
          } catch {
            DispatchQueue.main.async { self.finish(request, "invalidFormat") }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func finish(_ request: Request, _ value: String) {
    guard pending === request else { return }
    pending = nil
    request.picker = nil
    request.result(value)
  }
  private func photos(_ request: Request) {
    guard !request.cancelled else { finish(request, "cancelled"); return }
    func authorized(_ status: PHAuthorizationStatus) {
      guard !request.cancelled else { self.finish(request, "cancelled"); return }
      guard status == .authorized || status == .limited else {
        self.finish(request, "permissionDenied"); return
      }
      self.writePhotos(request)
    }
    let status = photoLibrary.status()
    if status == .notDetermined {
      photoLibrary.authorize { status in
        DispatchQueue.main.async { authorized(status) }
      }
    } else { authorized(status) }
  }
  private func writePhotos(_ request: Request) {
    guard let file = request.file else { finish(request, "unavailable"); return }
    photoLibrary.add(file) { saved, error in
      DispatchQueue.main.async {
        // Ignore cancellation after submission; only completion knows whether
        // a photo was actually committed. No UIImage decode/re-encoding.
        if saved { self.finish(request, "savedPhotos") }
        else if let error = error as NSError?, error.domain == PHPhotosErrorDomain,
                error.code == PHPhotosError.Code.invalidResource.rawValue {
          self.finish(request, "unsupportedFormat")
        } else { self.finish(request, "storageFailure") }
      }
    }
  }
  private func pick(_ request: Request) {
    guard !request.cancelled else { finish(request, "cancelled"); return }
    guard let host, host.viewIfLoaded?.window != nil,
          host.presentedViewController == nil, let file = request.file else {
      finish(request, "unavailable"); return
    }
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    request.picker = picker
    host.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let request = pending, request.picker === controller else { return }
    finish(request, urls.isEmpty ? "cancelled" : "savedFile")
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let request = pending, request.picker === controller else { return }
    finish(request, "cancelled")
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard let request = pending, request.picker === presentationController.presentedViewController else { return }
    finish(request, "cancelled")
  }
  enum Invalid: Error { case input }
  static func validate(_ args: [String: Any]?, temporary: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]) throws -> URL {
    guard let args, let path = args["path"] as? String, let name = args["name"] as? String,
          let size = args["size"] as? Int, let mime = args["mime"] as? String,
          size > 0, size <= 20 * 1024 * 1024,
          name.range(of: #"^shiori-[a-f0-9]{12}-[0-9]{1,16}\.(jpg|png|gif|webp|avif)$"#, options: .regularExpression) != nil
    else { throw Invalid.input }
    let input = URL(fileURLWithPath: path).standardizedFileURL
    let file = input.resolvingSymlinksInPath()
    let root = temporary.appendingPathComponent("shiori-image-export").resolvingSymlinksInPath()
    guard file == input, file.deletingLastPathComponent().deletingLastPathComponent() == root,
          file.deletingLastPathComponent().lastPathComponent.hasPrefix("export-"),
          file.lastPathComponent == name else { throw Invalid.input }
    let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == size else { throw Invalid.input }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: 4096) ?? Data()
    guard let format = format(header), name.hasSuffix(".\(format.0)"), mime == format.1 else { throw Invalid.input }
    return file
  }
  static func format(_ data: Data) -> (String, String)? {
    let bytes = [UInt8](data)
    func text(_ start: Int, _ count: Int) -> String {
      guard bytes.count >= start + count else { return "" }
      return String(bytes: bytes[start..<(start + count)], encoding: .ascii) ?? ""
    }
    if bytes.starts(with: [137,80,78,71,13,10,26,10]) { return ("png", "image/png") }
    if bytes.starts(with: [255,216,255]) { return ("jpg", "image/jpeg") }
    if ["GIF87a", "GIF89a"].contains(text(0,6)) { return ("gif", "image/gif") }
    if text(0,4) == "RIFF", text(8,4) == "WEBP" { return ("webp", "image/webp") }
    if text(4,4) == "ftyp", ["avif", "avis"].contains(text(8,4)) { return ("avif", "image/avif") }
    return nil
  }
}
