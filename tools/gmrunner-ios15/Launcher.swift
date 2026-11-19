// iOS 15 compatibility launcher for gmrunner. Based on the gmrunner scene/SDL
// integration by andronep; this adaptation is distributed under GPL-3.0-or-later.
import UIKit

@objc(GMRSceneDelegate)
final class GMRSceneDelegate: UIResponder, UIWindowSceneDelegate {
    static weak var scene: UIWindowScene?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        GMRSceneDelegate.scene = scene as? UIWindowScene
    }
    private func forward(_ selector: Selector) {
        let app = UIApplication.shared
        if let delegate = app.delegate as? NSObject, delegate.responds(to: selector) {
            delegate.perform(selector, with: app)
        }
    }
    func sceneWillResignActive(_ scene: UIScene) { forward(#selector(UIApplicationDelegate.applicationWillResignActive(_:))) }
    func sceneDidEnterBackground(_ scene: UIScene) { forward(#selector(UIApplicationDelegate.applicationDidEnterBackground(_:))) }
    func sceneWillEnterForeground(_ scene: UIScene) { forward(#selector(UIApplicationDelegate.applicationWillEnterForeground(_:))) }
    func sceneDidBecomeActive(_ scene: UIScene) { forward(#selector(UIApplicationDelegate.applicationDidBecomeActive(_:))) }
}

func waitForScene() -> UIWindowScene? {
    let deadline = Date(timeIntervalSinceNow: 10)
    while Date() < deadline {
        if let scene = GMRSceneDelegate.scene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene { return scene }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
    return nil
}

@_cdecl("gmr_ios_attach_window")
public func gmrIosAttachWindow(_ window: UnsafeMutableRawPointer) {
    let w = Unmanaged<UIWindow>.fromOpaque(window).takeUnretainedValue()
    if let scene = waitForScene() {
        w.windowScene = scene
        w.frame = scene.coordinateSpace.bounds
        w.makeKeyAndVisible()
        if #available(iOS 16.0, *) { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
}

@_cdecl("gmr_ios_safe_area")
public func gmrIosSafeArea(_ window: UnsafeMutableRawPointer, _ insets: UnsafeMutablePointer<Double>) {
    let i = Unmanaged<UIWindow>.fromOpaque(window).takeUnretainedValue().safeAreaInsets
    insets[0] = i.left; insets[1] = i.top; insets[2] = i.right; insets[3] = i.bottom
}

@_cdecl("gmr_ios_run_launcher")
public func gmrIosRunLauncher(_ root: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<CChar>, _ outSize: Int32) -> Int32 {
    guard outSize > 1 else { return 0 }
    let dir = URL(fileURLWithPath: String(cString: root))
    let window: UIWindow
    if let scene = waitForScene() { window = UIWindow(windowScene: scene) }
    else { window = UIWindow(frame: UIScreen.main.bounds) }
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    window.rootViewController = controller
    window.makeKeyAndVisible()
    var selected: URL?
    var refresh = true
    while selected == nil {
        if refresh && controller.presentedViewController == nil {
            refresh = false
            let list = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let names = ["data.win", "game.unx", "game.droid", "game.ios", "assets/game.unx", "assets/game.droid"]
            let games = list.filter { folder in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue &&
                    names.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let message = games.isEmpty ? "Chép thư mục game chứa data.win vào Tệp > Trên iPhone > gmRunner." : "Chọn game"
            let alert = UIAlertController(title: "gmRunner", message: message, preferredStyle: .alert)
            for game in games {
                alert.addAction(UIAlertAction(title: game.lastPathComponent, style: .default) { _ in selected = game })
            }
            alert.addAction(UIAlertAction(title: "Mở Tệp", style: .default) { _ in
                if let url = URL(string: "shareddocuments://" + dir.path) { UIApplication.shared.open(url) }
                refresh = true
            })
            alert.addAction(UIAlertAction(title: "Quét lại", style: .default) { _ in refresh = true })
            controller.present(alert, animated: true)
        }
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    window.isHidden = true
    window.rootViewController = nil
    let bytes = Array((selected?.path ?? "").utf8.prefix(Int(outSize) - 1))
    for (i, b) in bytes.enumerated() { out[i] = CChar(bitPattern: b) }
    out[bytes.count] = 0
    return 1
}

// Use gmrunner's built-in cross-platform game menu rather than the iOS 17+ SwiftUI sheet.
@_cdecl("gmr_ios_show_menu")
public func gmrIosShowMenu(_ json: UnsafePointer<CChar>) -> Int32 { return 0 }
@_cdecl("gmr_ios_menu_result")
public func gmrIosMenuResult() -> Int32 { return 0 }
