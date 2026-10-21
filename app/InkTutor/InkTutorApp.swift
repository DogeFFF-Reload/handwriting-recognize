import SwiftUI
import UIKit

@main
struct InkTutorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// App 可以随便缩放成窗口、横竖屏都行（不再要求全屏：iPadOS 26 的小窗里要求全屏的 App 拿不到真的窗口大小，只是被裁一块）。
/// 只有 CI 截图的演示（`-demo`）锁成横屏，画面和以前的截图一样。
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        demo ? .landscape : .all
    }
}
