import FirebaseCore
import SwiftUI

@main
struct AudiobooksTVApp: App {
    init() {
        // Optional sync: without the Firebase config the app runs exactly
        // as before, local-only.
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
            CloudProgressMirror.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
        }
    }
}
