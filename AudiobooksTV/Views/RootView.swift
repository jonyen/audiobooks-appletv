import SwiftUI

/// Gates the library behind Google sign-in so listening progress always
/// syncs, matching the web app.
///
/// A build with no Firebase / TV OAuth client plists can't sign in at all —
/// both files are gitignored, so any fresh clone of this repo is in that
/// state. Rather than becoming a dead end, such a build falls back to the
/// local-only library it had before sync existed.
struct RootView: View {
    @ObservedObject private var account = AccountModel.shared

    var body: some View {
        if !AccountModel.isConfigured {
            library
        } else if !account.didResolveInitialUser {
            // Firebase is still restoring a persisted session; showing the
            // gate here would flash it on every launch.
            Color.clear
        } else if account.user == nil {
            signInGate
        } else {
            library
        }
    }

    private var library: some View {
        NavigationStack {
            HomeView()
        }
    }

    private var signInGate: some View {
        VStack(spacing: 24) {
            Text("Audiobooks")
                .font(.system(size: 76, weight: .bold, design: .serif))
            AccountView()
        }
    }
}
