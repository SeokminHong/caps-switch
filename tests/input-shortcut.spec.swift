import XCTest

@testable import CapsSwitchCore

final class InputShortcutTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suite: String!
  private var backend: MemoryShortcuts!
  private var session: InputShortcutSession!
  private let original: [String: Any] = [
    "enabled": true, "value": ["type": "standard", "parameters": [32, 49, 262144]],
  ]

  override func setUp() {
    suite = "CapsSwitchTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    backend = MemoryShortcuts()
    backend.values = ["60": original, "61": ["enabled": false]]
    session = InputShortcutSession(backend: backend, defaults: defaults)
  }

  override func tearDown() { defaults.removePersistentDomain(forName: suite) }

  func testApplyAndRestorePreserveOtherShortcuts() throws {
    try session.apply(key: .f18)
    XCTAssertTrue(session.isConfigured(for: .f18))
    backend.values["61"] = ["enabled": true]
    try session.apply(key: .f18)
    try session.restore()
    XCTAssertTrue(
      NSDictionary(dictionary: backend.values["60"] as! [String: Any]).isEqual(to: original))
    XCTAssertEqual((backend.values["61"] as? [String: Bool])?["enabled"], true)
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testMissingOriginalIsRemovedOnRestore() throws {
    backend.values.removeValue(forKey: "60")
    try session.apply(key: .f13)
    try session.restore()
    XCTAssertNil(backend.values["60"])
  }

  func testExternalEditIsPreserved() throws {
    try session.apply(key: .f18)
    backend.values["60"] = ["enabled": false]
    try session.restore()
    XCTAssertEqual((backend.values["60"] as? [String: Bool])?["enabled"], false)
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testConflictingShortcutIsNotOverwritten() throws {
    try session.apply(key: .f18)
    let conflicting = backend.values["60"]
    try session.restore()
    backend.values["99"] = conflicting
    XCTAssertThrowsError(try session.apply(key: .f18))
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testRestorationSurvivesRelaunchAndActivationFailure() throws {
    try session.apply(key: .f18)
    backend.failActivation = true
    XCTAssertThrowsError(try session.restore())
    XCTAssertTrue(session.hasPendingRestoration)
    let relaunched = InputShortcutSession(backend: backend, defaults: defaults)
    backend.failActivation = false
    try relaunched.restore()
    XCTAssertFalse(relaunched.hasPendingRestoration)
    XCTAssertTrue(
      NSDictionary(dictionary: backend.values["60"] as! [String: Any]).isEqual(to: original))
    XCTAssertEqual(backend.activations, 3)
  }

  func testWriteFailureRetainsBackupForRetry() throws {
    try session.apply(key: .f18)
    backend.failWrite = true
    XCTAssertThrowsError(try session.restore())
    XCTAssertTrue(session.hasPendingRestoration)
    backend.failWrite = false
    try session.restore()
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testChoosesUnoccupiedKeyWithoutChangingOtherShortcuts() throws {
    try session.apply(key: .f18)
    let conflict = backend.values["60"]
    try session.restore()
    backend.values["99"] = conflict
    let before = backend.values
    XCTAssertEqual(try session.availableKey(preferred: .f18), .f13)
    XCTAssertTrue(NSDictionary(dictionary: backend.values).isEqual(to: before))
  }

  func testReportsWhenAllFunctionKeysAreReserved() throws {
    for key in FunctionKey.allCases {
      try session.apply(key: key)
      let conflict = backend.values["60"]
      try session.restore()
      backend.values["reserved-\(key.name)"] = conflict
    }
    XCTAssertThrowsError(try session.availableKey(preferred: .f18))
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testChangingKeyKeepsOriginalRestorationValue() throws {
    try session.apply(key: .f18)
    try session.apply(key: .f20)
    XCTAssertTrue(session.isConfigured(for: .f20))
    try session.restore()
    XCTAssertTrue(
      NSDictionary(dictionary: backend.values["60"] as! [String: Any]).isEqual(to: original))
  }

  func testExplicitApplyAfterUserEditBacksUpNewValue() throws {
    try session.apply(key: .f18)
    backend.values["60"] = ["enabled": false]
    try session.apply(key: .f18)
    try session.restore()
    XCTAssertEqual((backend.values["60"] as? [String: Bool])?["enabled"], false)
  }

  func testUnconfirmedRestoreRetainsJournal() throws {
    try session.apply(key: .f18)
    backend.ignoreWrite = true
    XCTAssertThrowsError(try session.restore())
    XCTAssertTrue(session.hasPendingRestoration)
    backend.ignoreWrite = false
    try session.restore()
    XCTAssertFalse(session.hasPendingRestoration)
  }

  func testApplyActivationFailureCanBeRolledBack() throws {
    backend.failActivation = true
    XCTAssertThrowsError(try session.apply(key: .f18))
    XCTAssertTrue(session.hasPendingRestoration)
    backend.failActivation = false
    try session.restore()
    XCTAssertTrue(
      NSDictionary(dictionary: backend.values["60"] as! [String: Any]).isEqual(to: original))
  }
}

private final class MemoryShortcuts: ShortcutBackend {
  var values: [String: Any] = [:]
  var failWrite = false
  var ignoreWrite = false
  var failActivation = false
  var activations = 0
  func read() throws -> [String: Any] { values }
  func write(_ shortcuts: [String: Any]) throws {
    if failWrite { throw KeyboardError.failure("write failure") }
    if !ignoreWrite { values = shortcuts }
  }
  func activate() throws {
    activations += 1
    if failActivation { throw KeyboardError.failure("activation failure") }
  }
}
