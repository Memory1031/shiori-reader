import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// The desktop import source owns copying; the native side only supplies URLs.
final class MacServices: NSObject, FlutterStreamHandler {
  static var shared: MacServices?
  static var pendingFiles: [String] = []
  private var sink: FlutterEventSink?
  private var queued: [[String]] = []
  private var queuedError: FlutterError?
  private weak var window: NSWindow?
  private var preparing = false
  private var updater: Process?
  private let queue = DispatchQueue(label: "dev.shiori.reader.update")
  private let menu: FlutterMethodChannel
  private var installation: URL { Bundle.main.bundleURL }
  private var workspace: URL { URL(fileURLWithPath: installation.path + ".update") }
  private var helper: URL { installation.appendingPathComponent("Contents/MacOS/shiori-updater") }

  init(controller: FlutterViewController, window: NSWindow) {
    self.window = window
    menu = FlutterMethodChannel(name: "dev.shiori.reader/menu", binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    Self.shared = self
    let messenger = controller.engine.binaryMessenger
    FlutterEventChannel(name: "dev.shiori.reader/file_drop", binaryMessenger: messenger).setStreamHandler(self)
    FlutterMethodChannel(name: "dev.shiori.reader/app", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "info": result(["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "", "build":Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "") ?? 0])
      case "availableStorage":
        let url = URL(fileURLWithPath: call.arguments as? String ?? NSHomeDirectory())
        result((try? url.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage)
      case "openRelease":
        guard let text = call.arguments as? String, let url = URL(string:text), url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/Memory1031/shiori-reader/releases/"), url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { result(false); return }
        result(NSWorkspace.shared.open(url))
      case "setCaption":
        if let args = call.arguments as? [String:Any], let rgb = args["color"] as? UInt32 {
          window.backgroundColor = NSColor(srgbRed:CGFloat((rgb >> 16)&255)/255, green:CGFloat((rgb >> 8)&255)/255, blue:CGFloat(rgb&255)/255, alpha:1)
          window.appearance = NSAppearance(named:(args["dark"] as? Bool == true) ? .darkAqua : .aqua)
        }
        result(true)
      default: result(FlutterMethodNotImplemented)
      }
    }
    FlutterMethodChannel(name:"dev.shiori.reader/update", binaryMessenger:messenger).setMethodCallHandler { [weak self] call, result in self?.update(call, result:result) }
    configureMenu()
    accept(Self.pendingFiles); Self.pendingFiles.removeAll()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    for paths in queued { events(paths) }; queued.removeAll()
    if let error = queuedError { events(error); queuedError = nil }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
  func accept(_ paths: [String]) {
    guard !paths.isEmpty else { return }
    guard paths.count <= 64 else { importError("batchLimit"); return }
    guard paths.allSatisfy({ ["txt","epub"].contains(URL(fileURLWithPath:$0).pathExtension.lowercased()) }) else { importError("unreadable"); return }
    if let sink = sink { sink(paths) }
    else if queued.reduce(0, {$0 + $1.count}) + paths.count <= 64 { queued.append(paths) }
    else { importError("batchLimit"); return }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps:true)
  }
  private func importError(_ code: String) {
    let error = FlutterError(code:code,message:nil,details:nil)
    if let sink = sink { sink(error) } else { queuedError = error }
  }
  @objc private func openBook() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, UTType(filenameExtension:"epub") ?? .data]; panel.allowsMultipleSelection = true
    panel.begin { [weak self] response in if response == .OK { self?.accept(panel.urls.map(\.path)) } }
  }
  @objc private func preferences() { menu.invokeMethod("settings",arguments:nil) }
  private func configureMenu() {
    guard let main = NSApp.mainMenu else { return }
    let zh = Locale.preferredLanguages.first?.hasPrefix("zh") == true
    if let app = main.items.first?.submenu, let item = app.items.first(where: {$0.keyEquivalent == ","}) {
      item.title = zh ? "设置…" : "Settings…"; item.target = self; item.action = #selector(preferences)
    }
    let file = NSMenu(title:zh ? "文件" : "File")
    let open = NSMenuItem(title:zh ? "导入书籍…" : "Import Books…", action:#selector(openBook), keyEquivalent:"o"); open.target = self; file.addItem(open)
    let close = NSMenuItem(title:zh ? "关闭窗口" : "Close Window", action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"); file.addItem(close)
    let item = NSMenuItem(); item.title = file.title; item.submenu = file; main.insertItem(item, at:1)
    // Reader shortcuts handle Cmd+F/G; remove the template's unrelated text Find menu.
    for menu in main.items.compactMap(\.submenu) {
      for item in menu.items where item.submenu?.items.contains(where:{$0.action == NSSelectorFromString("performFindPanelAction:")}) == true { menu.removeItem(item) }
    }
  }
  private func run(_ executable: URL, _ arguments: [String]) throws -> String {
    let process = Process(); process.executableURL = executable; process.arguments = arguments
    let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
    try process.run(); process.waitUntilExit()
    if process.terminationStatus != 0 {
      let code = String(data:errors.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "installation"
      throw NSError(domain:"ShioriUpdate",code:1,userInfo:[NSLocalizedDescriptionKey:code])
    }
    return String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "failed"
  }
  private func update(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "exit" { result(nil); exit(0) }
    guard !preparing else { result(FlutterError(code:"busy",message:nil,details:nil)); return }
    if call.method == "status" {
      preparing = true
      queue.async { [self] in
        self.finish(result) {
          for attempt in 0..<50 {
            do { return try self.run(self.helper,["recover", self.installation.path]) }
            catch { if (error as NSError).localizedDescription != "busy" || attempt == 49 { throw error } }
            Thread.sleep(forTimeInterval:0.1)
          }
          return "installing"
        }
      }
    } else if call.method == "prepare", let args = call.arguments as? [String:Any], let path = args["path"] as? String, let manifest = args["manifest"] as? FlutterStandardTypedData, let signature = args["signature"] as? FlutterStandardTypedData {
      guard manifest.data.count <= 4*1024*1024, signature.data.count == 384 else { result(FlutterError(code:"verification",message:nil,details:nil)); return }
      preparing = true
      queue.async { [self] in
        self.finish(result) {
          let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at:input,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
          defer { try? FileManager.default.removeItem(at:input) }
          let raw = input.appendingPathComponent("manifest"), sig = input.appendingPathComponent("signature")
          try manifest.data.write(to:raw); try signature.data.write(to:sig)
          return try self.run(self.helper,["prepare",self.installation.path,path,raw.path,sig.path])
        }
      }
    } else if call.method == "start" {
      preparing = true
      queue.async { [self] in
        self.finish(result) {
          let fm = FileManager.default, handoff = self.workspace.appendingPathComponent("handoff")
          if fm.fileExists(atPath:handoff.path) { try fm.removeItem(at:handoff) }
          try fm.copyItem(at:self.helper,to:handoff)
          let started = self.workspace.appendingPathComponent("started.json"); try? fm.removeItem(at:started)
          let process = Process(); process.executableURL = handoff; process.arguments = ["run",self.installation.path,String(getpid())]
          process.standardOutput = FileHandle.nullDevice; let errors = Pipe(); process.standardError = errors
          try process.run(); self.updater = process
          let deadline = Date().addingTimeInterval(15)
          while Date() < deadline && process.isRunning {
            if let data = try? Data(contentsOf:started), let record = (try? JSONSerialization.jsonObject(with:data)) as? [String:Int], record["pid"] == Int(process.processIdentifier), record["parent"] == Int(getpid()) { return "installing" }
            Thread.sleep(forTimeInterval:0.05)
          }
          if process.isRunning { process.terminate() }
          let code = String(data:errors.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "installation"
          throw NSError(domain:"ShioriUpdate",code:1,userInfo:[NSLocalizedDescriptionKey:code])
        }
      }
    } else { result(FlutterMethodNotImplemented) }
  }
  private func finish(_ result: @escaping FlutterResult, work: () throws -> String) {
    let value: Any
    do { value = try work() } catch { value = FlutterError(code:(error as NSError).localizedDescription,message:nil,details:nil) }
    DispatchQueue.main.async { self.preparing = false; result(value) }
  }
}
