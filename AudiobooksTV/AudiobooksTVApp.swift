import SwiftUI

@main
struct AudiobooksTVApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if Secrets.esvAPIKey.isEmpty {
                    SetupView()
                } else {
                    BookListView()
                }
            }
        }
    }
}
