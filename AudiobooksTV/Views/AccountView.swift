import SwiftUI

/// Sign in with Apple to sync listening progress with the web app.
struct AccountView: View {
    @ObservedObject private var account = AccountModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            if !AccountModel.isConfigured {
                Text("Sync is not configured in this build.")
                    .foregroundStyle(.secondary)
            } else if let user = account.user {
                Text("Signed in\(user.displayName.map { " as \($0)" } ?? "")")
                Text("Progress syncs with the web app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sign Out") { account.signOut() }
            } else {
                Text("Sign in to sync your listening progress with the web app.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 800)
                Button(" Sign in with Apple") { account.signIn() }
            }

            if let error = account.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Button("Done") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(64)
    }
}
