import CoreImage.CIFilterBuiltins
import SwiftUI

/// Sign in with Google (device flow) to sync listening progress with the
/// web app: shows a short code + QR, approved on the user's phone.
struct AccountView: View {
    /// Dismisses the in-app account sheet. Nil at the sign-in gate, where
    /// there is nothing behind this screen to return to.
    var onDone: (() -> Void)?

    @ObservedObject private var account = AccountModel.shared

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
            } else if let pairing = account.pairing {
                Text("On your phone, scan the code or visit \(pairing.verificationURL), then enter:")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Text(pairing.userCode)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                if let qr = Self.qrImage(for: pairing.verificationURL) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                }
                ProgressView()
                Button("Cancel") { account.cancelSignIn() }
            } else {
                Text("Sign in with Google to sync your listening progress with the web app.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 800)
                Button("Sign in with Google") { account.signIn() }
            }

            if let error = account.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if let onDone {
                Button("Done") { onDone() }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(64)
        .onDisappear { account.cancelSignIn() }
    }

    private static func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
