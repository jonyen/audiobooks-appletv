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
