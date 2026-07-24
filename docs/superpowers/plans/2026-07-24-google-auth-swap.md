# Google Auth Swap (Apple → Google) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Sign in with Apple with Google sign-in — a popup on web, the OAuth device flow (QR + short code) on tvOS — removing the paid Apple Developer Program dependency while landing both platforms on the same Firebase `uid`.

**Architecture:** Web swaps `OAuthProvider("apple.com")` for `GoogleAuthProvider` (two-line change). tvOS replaces the ASAuthorization flow in `AccountModel` with Google's "TVs and Limited Input Devices" device flow: request a device code, show the user code + QR, poll the token endpoint, exchange the returned Google ID token via `GoogleAuthProvider.credential`. Pure decode/decision logic lives in `AudiobooksCore` (testable, no networking); networking and Firebase stay in the app target. The Sign in with Apple entitlement is removed. The sync layer (Firestore docs, merge logic, mirrors) is untouched — it only ever consumed the Firebase `uid`.

**Tech Stack:** Firebase JS SDK (GoogleAuthProvider), Google OAuth 2.0 device flow (RFC 8628), FirebaseAuth iOS `GoogleAuthProvider.credential`, CoreImage QR generation.

**Spec:** `docs/superpowers/specs/2026-07-23-web-port-synced-progress-design.md` (see the 2026-07-24 amendment in Goal/Authentication)

## Global Constraints

- This repo is public: the TV OAuth client ID/secret must NOT be committed. They load from `AudiobooksTV/GoogleTVClient.plist` (gitignored, like `GoogleService-Info.plist`); a `GoogleTVClient.example.plist` is committed. Google treats limited-input client secrets as non-confidential, but they stay out of git anyway.
- `AccountModel`'s consumed API surface must not change: `AccountModel.shared`, `@Published user`, `@Published errorMessage`, `signIn()`, `signOut()`, `static isConfigured`. `CloudProgressMirror`, `AudiobooksTVApp`, and `HomeView` must not need edits (Task 3 may only touch `AccountModel.swift`, `AccountView.swift`, the entitlements removal, and config files).
- Device flow endpoints: `https://oauth2.googleapis.com/device/code` (fields `client_id`, `scope="openid email profile"`) and `https://oauth2.googleapis.com/token` (fields `client_id`, `client_secret`, `device_code`, `grant_type="urn:ietf:params:oauth:grant-type:device_code"`). Poll handling: `authorization_pending` → keep interval; `slow_down` → interval + 5 s; `access_denied` / `expired_token` → user-facing failure; overall deadline = `expires_in`.
- Signed out or unconfigured (missing either plist), tvOS behavior must not change at all.
- Web commands run from `web/`; Swift logic tests run with `swift test`; the app must build for the tvOS simulator after Task 3.
- Commit after every task; commit messages end with the standard co-author trailer.

---

### Task 1: Web — Google provider swap + docs

**Files:**
- Modify: `web/src/lib/firebase.ts`, `web/src/components/SignIn.tsx`, `web/README.md`, `README.md`

**Interfaces:**
- Produces: `signInWithGoogle(): Promise<void>` in `firebase.ts` (replacing `signInWithApple`); `SignIn.tsx` is its only caller. Everything else in `firebase.ts` (auth, db, signOutUser, useUser) is unchanged.

- [ ] **Step 1: Swap the provider in `web/src/lib/firebase.ts`**

Change the import line and the sign-in function (leave the rest of the file identical):

```ts
import {
  GoogleAuthProvider,
  getAuth,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
  type User,
} from "firebase/auth";
```

```ts
export async function signInWithGoogle(): Promise<void> {
  await signInWithPopup(auth, new GoogleAuthProvider());
}
```

(Delete `signInWithApple` and the now-unused `OAuthProvider` import.)

- [ ] **Step 2: Update `web/src/components/SignIn.tsx`**

Replace the import and the button:

```tsx
import { signInWithGoogle } from "../lib/firebase";
```

```tsx
      <button
        onClick={() => {
          setError(null);
          signInWithGoogle().catch((e: Error) => setError(e.message));
        }}
      >
        Sign in with Google
      </button>
```

- [ ] **Step 3: Update the docs**

In `web/README.md`, replace the "Sign in with Apple" setup step (step 3) with:

````markdown
3. **Google sign-in**:
   - Firebase console → Authentication → Sign-in method → **Google**: enable
     it (no keys needed for the web popup).
   - For the Apple TV app's QR sign-in: Google Cloud console (same project)
     → APIs & Services → Credentials → Create Credentials → OAuth client ID
     → type **TVs and Limited Input Devices**. Copy the client ID and secret
     into `AudiobooksTV/GoogleTVClient.plist` (see
     `AudiobooksTV/GoogleTVClient.example.plist`; the real file is
     gitignored).
````

Also in `web/README.md`: in step 5, drop the "and to the Apple Services ID's web domains" clause (authorized domains in Firebase remain required). In the intro line, change "Sign in with Apple" to "Google sign-in".

In the root `README.md` Web section, change "synced through Sign in with Apple + Firestore" to "synced through Google sign-in + Firestore".

- [ ] **Step 4: Verify**

Run: `cd web && npm test && npm run build && npx tsc --noEmit`
Expected: 61 tests pass, build succeeds, typecheck clean (confirms no lingering `signInWithApple` references).

- [ ] **Step 5: Commit**

```bash
git add web/src/lib/firebase.ts web/src/components/SignIn.tsx web/README.md README.md
git commit -m "feat: swap web sign-in from Apple to Google"
```

---

### Task 2: Core — device-flow models + poll decision logic

**Files:**
- Create: `AudiobooksTV/Core/GoogleDeviceAuth.swift`
- Test: `Tests/AudiobooksCoreTests/GoogleDeviceAuthTests.swift`

**Interfaces:**
- Produces (pure Foundation, no networking — Task 3 consumes all of these):
  - `struct DeviceCodeResponse: Decodable, Equatable { deviceCode, userCode, verificationURL: String; expiresIn: Int; interval: Int? }` (snake_case coding keys per Google's response)
  - `struct DeviceTokenResponse: Decodable, Equatable { idToken, accessToken: String }`
  - `enum DevicePollOutcome: Equatable { case authorized(DeviceTokenResponse); case keepPolling(afterSeconds: Double); case failed(String) }`
  - `GoogleDeviceAuth.pollOutcome(body: Data, interval: Double) -> DevicePollOutcome`

- [ ] **Step 1: Write the failing test** — `Tests/AudiobooksCoreTests/GoogleDeviceAuthTests.swift`:

```swift
import XCTest
@testable import AudiobooksCore

final class GoogleDeviceAuthTests: XCTestCase {
    func testDecodesDeviceCodeResponse() throws {
        let json = #"{"device_code":"dc123","user_code":"ABCD-EFGH","verification_url":"https://www.google.com/device","expires_in":1800,"interval":5}"#
        let decoded = try JSONDecoder().decode(DeviceCodeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.deviceCode, "dc123")
        XCTAssertEqual(decoded.userCode, "ABCD-EFGH")
        XCTAssertEqual(decoded.verificationURL, "https://www.google.com/device")
        XCTAssertEqual(decoded.expiresIn, 1800)
        XCTAssertEqual(decoded.interval, 5)
    }

    func testAuthorizedOutcomeFromTokenBody() {
        let json = #"{"access_token":"at","id_token":"idt","expires_in":3599,"token_type":"Bearer","scope":"openid"}"#
        let outcome = GoogleDeviceAuth.pollOutcome(body: Data(json.utf8), interval: 5)
        XCTAssertEqual(outcome, .authorized(DeviceTokenResponse(idToken: "idt", accessToken: "at")))
    }

    func testPendingKeepsPollingAtSameInterval() {
        let outcome = GoogleDeviceAuth.pollOutcome(
            body: Data(#"{"error":"authorization_pending"}"#.utf8), interval: 5)
        XCTAssertEqual(outcome, .keepPolling(afterSeconds: 5))
    }

    func testSlowDownBacksOffByFiveSeconds() {
        let outcome = GoogleDeviceAuth.pollOutcome(
            body: Data(#"{"error":"slow_down"}"#.utf8), interval: 5)
        XCTAssertEqual(outcome, .keepPolling(afterSeconds: 10))
    }

    func testDeniedAndExpiredFailWithUserFacingMessages() {
        XCTAssertEqual(
            GoogleDeviceAuth.pollOutcome(body: Data(#"{"error":"access_denied"}"#.utf8), interval: 5),
            .failed("Sign-in was declined."))
        XCTAssertEqual(
            GoogleDeviceAuth.pollOutcome(body: Data(#"{"error":"expired_token"}"#.utf8), interval: 5),
            .failed("The code expired. Try again."))
    }

    func testGarbageBodyFails() {
        if case .failed = GoogleDeviceAuth.pollOutcome(body: Data("not json".utf8), interval: 5) {
        } else {
            XCTFail("expected .failed for garbage body")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test`
Expected: FAIL — `DeviceCodeResponse` / `GoogleDeviceAuth` not found.

- [ ] **Step 3: Implement** — `AudiobooksTV/Core/GoogleDeviceAuth.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test`
Expected: all 6 new tests PASS (71 total, no regressions).

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/GoogleDeviceAuth.swift Tests/AudiobooksCoreTests/GoogleDeviceAuthTests.swift
git commit -m "feat: Google device-flow models and poll decision logic in Core"
```

---

### Task 3: tvOS — device-flow sign-in, QR account view, drop the Apple entitlement

**Files:**
- Rewrite: `AudiobooksTV/Services/AccountModel.swift`, `AudiobooksTV/Views/AccountView.swift`
- Create: `AudiobooksTV/GoogleTVClient.example.plist`
- Delete: `AudiobooksTV/AudiobooksTV.entitlements`
- Modify: `AudiobooksTV.xcodeproj/project.pbxproj` (remove both `CODE_SIGN_ENTITLEMENTS` lines), `.gitignore` (add `AudiobooksTV/GoogleTVClient.plist`)

**Interfaces:**
- Consumes: `DeviceCodeResponse`, `DeviceTokenResponse`, `DevicePollOutcome`, `GoogleDeviceAuth.pollOutcome` (Task 2); `GoogleAuthProvider.credential(withIDToken:accessToken:)` (FirebaseAuth).
- Produces: same `AccountModel` API as before (`shared`, `user`, `errorMessage`, `signIn()`, `signOut()`, `isConfigured`) plus `@Published pairing: Pairing?` (`{ userCode, verificationURL }`) and `cancelSignIn()` consumed only by `AccountView`. No other file may need changes.

- [ ] **Step 1: Rewrite `AudiobooksTV/Services/AccountModel.swift`** (full replacement):

```swift
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
    /// Non-nil while a device-flow pairing is awaiting phone approval.
    @Published private(set) var pairing: Pairing?
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?

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
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
    }

    func signIn() {
        guard pollTask == nil, let client = Self.tvClient else { return }
        errorMessage = nil
        pollTask = Task { [weak self] in
            await self?.runDeviceFlow(client: client)
            self?.pollTask = nil
            self?.pairing = nil
        }
    }

    /// Stops an in-progress pairing (sheet dismissed or Cancel pressed).
    func cancelSignIn() {
        pollTask?.cancel()
        pollTask = nil
        pairing = nil
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: Device flow

    private func runDeviceFlow(client: (id: String, secret: String)) async {
        do {
            let code = try await Self.requestDeviceCode(clientID: client.id)
            pairing = Pairing(userCode: code.userCode, verificationURL: code.verificationURL)
            var interval = Double(code.interval ?? 5)
            let deadline = Date().addingTimeInterval(Double(code.expiresIn))
            while Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                let body = try await Self.pollToken(client: client, deviceCode: code.deviceCode)
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
            errorMessage = "The code expired. Try again."
        } catch is CancellationError {
            // User dismissed the pairing; nothing to report.
        } catch {
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
```

(This removes the `AuthenticationServices`, `CryptoKit`, and `UIKit` imports and all nonce/ASAuthorization code.)

- [ ] **Step 2: Rewrite `AudiobooksTV/Views/AccountView.swift`** (full replacement):

```swift
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Sign in with Google (device flow) to sync listening progress with the
/// web app: shows a short code + QR, approved on the user's phone.
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

            Button("Done") { dismiss() }
                .foregroundStyle(.secondary)
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
```

- [ ] **Step 3: Config plumbing**

`AudiobooksTV/GoogleTVClient.example.plist` (committed):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>1234567890-example.apps.googleusercontent.com</string>
	<key>CLIENT_SECRET</key>
	<string>example-not-a-real-secret</string>
</dict>
</plist>
```

Append to `.gitignore`:

```
AudiobooksTV/GoogleTVClient.plist
```

Delete `AudiobooksTV/AudiobooksTV.entitlements`, and remove both `CODE_SIGN_ENTITLEMENTS = AudiobooksTV/AudiobooksTV.entitlements;` lines (Debug + Release target configs) from `AudiobooksTV.xcodeproj/project.pbxproj`. Nothing else in the pbxproj changes — the Firebase package refs stay.

- [ ] **Step 4: Verify**

Run: `swift test`
Expected: all suites PASS (the app-target files aren't compiled by SPM, but Core must stay green).

Run: `xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV -destination 'platform=tvOS Simulator,name=Apple TV' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED with no `GoogleTVClient.plist` present (the example plist is picked up by the synced folder but has a different name, so `isConfigured` is false → account sheet shows "Sync is not configured in this build.").

Also grep the app sources for leftovers: `grep -rn "AuthenticationServices\|applesignin\|signInWithApple\|ASAuthorization" AudiobooksTV/ web/src/` — expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add -A AudiobooksTV AudiobooksTV.xcodeproj .gitignore
git commit -m "feat: Google device-flow sign-in on tvOS; drop Sign in with Apple"
```

---

## Verification

1. `cd web && npm test && npm run build && npx tsc --noEmit` — green.
2. `swift test` — green, including the 6 new GoogleDeviceAuth tests.
3. tvOS simulator build succeeds; unconfigured build shows "Sync is not configured".
4. Live (after the user creates the TV OAuth client and enables the Google provider): web popup sign-in works; tvOS shows code + QR, approving on a phone signs the TV into the same account; progress syncs both ways.
