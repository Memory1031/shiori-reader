import UIKit

@main
final class FixtureApp: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = FixtureViewController()
    window?.makeKeyAndVisible()
    return true
  }
}

final class FixtureViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 24
    for (index, title) in ["Share TXT", "Share EPUB", "Share multiple"].enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(title, for: .normal)
      button.tag = index
      button.addTarget(self, action: #selector(share), for: .touchUpInside)
      stack.addArrangedSubview(button)
    }
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }
  @objc private func share(_ button: UIButton) {
    let root = FileManager.default.temporaryDirectory
    let txt = root.appendingPathComponent("share-fixture.txt")
    let epub = root.appendingPathComponent("share-fixture.epub")
    try! Data("Offline TXT fixture".utf8).write(to: txt)
    // Intake fixture only; real EPUB parsing is a separate task.
    try! Data([0x50, 0x4b, 3, 4, 65]).write(to: epub)
    let items = button.tag == 2 ? [txt, epub] : [button.tag == 0 ? txt : epub]
    let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
    share.popoverPresentationController?.sourceView = button
    present(share, animated: true)
  }
}
