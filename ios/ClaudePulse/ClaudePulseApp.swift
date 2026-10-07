import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Indispensable même quand iOS réveille l'app en arrière-plan après un push-to-start :
        // c'est ici qu'on récupère le jeton de la nouvelle Live Activity pour le backend.
        ActivityManager.shared.start()
        return true
    }
}

@main
struct ClaudePulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ActivityManager.shared)
        }
    }
}
