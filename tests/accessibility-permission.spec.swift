import XCTest

@testable import CapsSwitchCore

final class AccessibilityPermissionTests: XCTestCase {
  func testGrantedPermissionNeverPrompts() {
    var requests = 0
    let permission = AccessibilityPermission(checkTrust: { true }, request: { requests += 1 })
    permission.requestIfNeeded()
    permission.requestIfNeeded()
    XCTAssertTrue(permission.isTrusted)
    XCTAssertEqual(requests, 0)
  }

  func testUnapprovedPermissionPromptsOnlyOncePerRun() {
    var requests = 0
    let permission = AccessibilityPermission(checkTrust: { false }, request: { requests += 1 })
    permission.requestIfNeeded()
    permission.requestIfNeeded()
    XCTAssertEqual(requests, 1)
    XCTAssertFalse(permission.isTrusted)
  }

  func testTrustChangesAreObservedWithoutPrompting() {
    var trusted = false
    var requests = 0
    let permission = AccessibilityPermission(checkTrust: { trusted }, request: { requests += 1 })
    XCTAssertFalse(permission.isTrusted)
    trusted = true
    XCTAssertTrue(permission.isTrusted)
    permission.requestIfNeeded()
    trusted = false
    XCTAssertFalse(permission.isTrusted)
    XCTAssertEqual(requests, 0)
    permission.requestIfNeeded()
    trusted = true
    permission.requestIfNeeded()
    XCTAssertEqual(requests, 1)
  }
}
