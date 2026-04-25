import XCTest
import AVFoundation
@testable import EarTrainLib

@MainActor
final class MicrophonePermissionTests: XCTestCase {

    func testIsAuthorizedWhenGranted() async {
        // Can't force AVCaptureDevice status in tests, but we can verify
        // the computed properties are consistent with each other.
        let manager = MicrophonePermissionManager()
        // isAuthorized and isBlocked must never both be true
        XCTAssertFalse(manager.isAuthorized && manager.isBlocked)
    }

    func testIsBlockedForDeniedStatus() {
        // Verify the logic mapping: denied → isBlocked, not isAuthorized
        let deniedStatuses: [AVAuthorizationStatus] = [.denied, .restricted]
        for status in deniedStatuses {
            XCTAssertTrue(status.isBlockingMicAccess, "\(status) should block access")
            XCTAssertFalse(status.isAuthorizedMicAccess, "\(status) should not be authorized")
        }
    }

    func testIsAuthorizedForGrantedStatus() {
        XCTAssertTrue(AVAuthorizationStatus.authorized.isAuthorizedMicAccess)
        XCTAssertFalse(AVAuthorizationStatus.authorized.isBlockingMicAccess)
    }

    func testNotDeterminedIsNeitherBlockedNorAuthorized() {
        XCTAssertFalse(AVAuthorizationStatus.notDetermined.isBlockingMicAccess)
        XCTAssertFalse(AVAuthorizationStatus.notDetermined.isAuthorizedMicAccess)
    }

    func testSystemSettingsURLIsValid() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        XCTAssertNotNil(url, "System Settings URL must be valid")
    }
}
