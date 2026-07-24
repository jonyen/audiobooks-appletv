import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import SwiftUI
import UIKit

/// Firebase-backed account state. Sign-in is optional: everything degrades
/// to local-only behavior when Firebase isn't configured or no one signed in.
@MainActor
final class AccountModel: NSObject, ObservableObject {
    static let shared = AccountModel()

    @Published private(set) var user: FirebaseAuth.User?
    @Published var errorMessage: String?

    private var currentNonce: String?

    /// True when GoogleService-Info.plist was present and configure() ran.
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    override private init() {
        super.init()
        guard Self.isConfigured else { return }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
    }

    func signIn() {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension AccountModel: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Sign-in failed. Try again."
                return
            }
            let firebaseCredential = OAuthProvider.credential(
                providerID: .apple, idToken: token, rawNonce: nonce
            )
            do {
                try await Auth.auth().signIn(with: firebaseCredential)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension AccountModel: ASAuthorizationControllerPresentationContextProviding {
    // Documented to be called on the main thread.
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
