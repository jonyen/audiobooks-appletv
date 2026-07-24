import FirebaseAuth
import FirebaseCore
import SwiftUI

/// Firebase-backed account state, signed in via Google's OAuth device flow
/// (short code + QR approved on a phone — no keyboard entry on the TV).
/// Sign-in is optional: everything degrades to local-only behavior when
/// Firebase or the TV OAuth client isn't configured, or no one signed in.
@MainActor
final class AccountModel: ObservableObject {
    static let shared = AccountModel()

    struct Pairing: Equatable {
        let userCode: String
        let verificationURL: String
    }

    @Published private(set) var user: FirebaseAuth.User?
    /// False until Firebase reports its first auth state, which it does
    /// asynchronously after restoring any persisted session. Lets the
    /// sign-in gate tell "still restoring" from "signed out" instead of
    /// flashing the sign-in screen on every launch.
    @Published private(set) var didResolveInitialUser = false
    /// Non-nil while a device-flow pairing is awaiting phone approval.
    @Published private(set) var pairing: Pairing?
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    /// Bumped on each new sign-in attempt and on cancellation so a dying
    /// task's completion handler can detect it's stale and skip cleanup.
    private var flowGeneration = 0

    /// True when both GoogleService-Info.plist and GoogleTVClient.plist
    /// are present. Missing either → account UI shows "not configured".
    static var isConfigured: Bool { FirebaseApp.app() != nil && tvClient != nil }

    /// TV OAuth client ("TVs and Limited Input Devices" type), from the
    /// gitignored GoogleTVClient.plist — see GoogleTVClient.example.plist.
    private static let tvClient: (id: String, secret: String)? = {
        guard let url = Bundle.main.url(forResource: "GoogleTVClient", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let id = dict["CLIENT_ID"] as? String, !id.isEmpty,
              let secret = dict["CLIENT_SECRET"] as? String, !secret.isEmpty else { return nil }
        return (id, secret)
    }()

    private init() {
        guard FirebaseApp.app() != nil else { return }
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.didResolveInitialUser = true
            }
        }
    }

    func signIn() {
        guard pollTask == nil, let client = Self.tvClient else { return }
        errorMessage = nil
        flowGeneration += 1
        let generation = flowGeneration
        pollTask = Task { [weak self] in
            await self?.runDeviceFlow(client: client, generation: generation)
            if let self, self.flowGeneration == generation {
                self.pollTask = nil
                self.pairing = nil
            }
        }
    }

    /// Stops an in-progress pairing (sheet dismissed or Cancel pressed).
    func cancelSignIn() {
        flowGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        pairing = nil
        errorMessage = nil
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: Device flow

    private func runDeviceFlow(client: (id: String, secret: String), generation: Int) async {
        do {
            let code = try await Self.requestDeviceCode(clientID: client.id)
            guard flowGeneration == generation else { return }
            pairing = Pairing(userCode: code.userCode, verificationURL: code.verificationURL)
            var interval = Double(code.interval ?? 5)
            let deadline = Date().addingTimeInterval(Double(code.expiresIn))
            while Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard flowGeneration == generation else { return }
                let body: Data
                do {
                    body = try await Self.pollToken(client: client, deviceCode: code.deviceCode)
                } catch let error as URLError where error.code != .cancelled {
                    // Transient transport failure: skip this round, keep the
                    // pairing alive — the expires_in deadline still bounds us.
                    continue
                }
                guard flowGeneration == generation else { return }
                switch GoogleDeviceAuth.pollOutcome(body: body, interval: interval) {
                case .authorized(let token):
                    let credential = GoogleAuthProvider.credential(
                        withIDToken: token.idToken, accessToken: token.accessToken)
                    try await Auth.auth().signIn(with: credential)
                    return
                case .keepPolling(let next):
                    interval = next
                case .failed(let message):
                    errorMessage = message
                    return
                }
            }
            guard flowGeneration == generation else { return }
            errorMessage = "The code expired. Try again."
        } catch is CancellationError {
            // User dismissed the pairing; nothing to report.
        } catch let error as URLError where error.code == .cancelled {
            // Same: cancellation landed mid-request instead of mid-sleep.
        } catch {
            guard flowGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func requestDeviceCode(clientID: String) async throws -> DeviceCodeResponse {
        let data = try await post(
            url: "https://oauth2.googleapis.com/device/code",
            fields: ["client_id": clientID, "scope": "openid email profile"]
        )
        guard let code = try? JSONDecoder().decode(DeviceCodeResponse.self, from: data) else {
            throw NSError(domain: "AccountModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not start Google sign-in. Check the TV client configuration.",
            ])
        }
        return code
    }

    private static func pollToken(
        client: (id: String, secret: String), deviceCode: String
    ) async throws -> Data {
        try await post(url: "https://oauth2.googleapis.com/token", fields: [
            "client_id": client.id,
            "client_secret": client.secret,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
    }

    private static func post(url: String, fields: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
