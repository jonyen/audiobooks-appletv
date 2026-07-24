import Foundation

/// Models and pure decision logic for Google's OAuth 2.0 device flow
/// ("TVs and Limited Input Devices", RFC 8628). Networking lives in the
/// app target; this file is URLSession-free so `swift test` covers it.

struct DeviceCodeResponse: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let expiresIn: Int
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

struct DeviceTokenResponse: Decodable, Equatable {
    let idToken: String
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
    }

    init(idToken: String, accessToken: String) {
        self.idToken = idToken
        self.accessToken = accessToken
    }
}

enum DevicePollOutcome: Equatable {
    case authorized(DeviceTokenResponse)
    case keepPolling(afterSeconds: Double)
    case failed(String)
}

enum GoogleDeviceAuth {
    /// Interprets one token-endpoint response body during device-flow
    /// polling. `interval` is the current polling interval in seconds;
    /// Google's `slow_down` asks for +5 s (RFC 8628 §3.5).
    static func pollOutcome(body: Data, interval: Double) -> DevicePollOutcome {
        if let token = try? JSONDecoder().decode(DeviceTokenResponse.self, from: body) {
            return .authorized(token)
        }
        struct ErrorBody: Decodable { let error: String? }
        let error = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        switch error {
        case "authorization_pending": return .keepPolling(afterSeconds: interval)
        case "slow_down": return .keepPolling(afterSeconds: interval + 5)
        case "access_denied": return .failed("Sign-in was declined.")
        case "expired_token": return .failed("The code expired. Try again.")
        default: return .failed("Google sign-in failed (\(error ?? "unknown error")).")
        }
    }
}
