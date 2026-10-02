import XCTest

@testable import CapsSwitchCore

final class KeyMappingTests: XCTestCase {
  func testAllFunctionKeysApplyAndRestore() throws {
    for key in FunctionKey.allCases {
      let backend = MemoryBackend(mappings: [previousCaps, unrelated])
      let session = MappingSession(backend: backend, targetKey: key)
      try session.apply()
      XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, MappingPolicy.mapping(to: key)])
      try session.restore()
      XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, previousCaps])
    }
  }

  private let unrelated: KeyMapping = [
    MappingPolicy.sourceKey: 0x7_0000_0004, MappingPolicy.destinationKey: 0x7_0000_0005,
  ]
  private let previousCaps: KeyMapping = [
    MappingPolicy.sourceKey: MappingPolicy.capsLockUsage,
    MappingPolicy.destinationKey: 0x7_0000_0029,
  ]

  func testCapsMappingPreservesOtherKeys() {
    XCTAssertEqual(
      MappingPolicy.applying(to: [unrelated, previousCaps]), [unrelated, MappingPolicy.capsToF18])
  }

  func testRestorePreservesChangesToOtherKeys() {
    XCTAssertEqual(
      MappingPolicy.restoring(
        current: [unrelated, MappingPolicy.capsToF18], original: [previousCaps]),
      [unrelated, previousCaps]
    )
  }

  func testRepeatedApplyKeepsOriginalCapsMapping() throws {
    let backend = MemoryBackend(mappings: [unrelated, previousCaps])
    let session = MappingSession(backend: backend)
    try session.apply()
    try session.apply()
    try session.restore()
    XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, previousCaps])
    XCTAssertFalse(session.isActive)
  }

  func testRestoreDoesNotOverwriteExternalCapsChange() throws {
    let backend = MemoryBackend(mappings: [])
    let session = MappingSession(backend: backend)
    try session.apply()
    try backend.write(id: 1, mappings: [previousCaps])
    XCTAssertThrowsError(try session.restore())
    XCTAssertEqual(backend.keyboards[0].mappings, [previousCaps])
  }

  func testNoKeyboardReportsFailure() {
    let backend = MemoryBackend(mappings: [])
    backend.keyboards = []
    XCTAssertThrowsError(try MappingSession(backend: backend).apply())
  }

  func testReconcileRecoversResetMappingForEveryFunctionKey() throws {
    for key in FunctionKey.allCases {
      let backend = MemoryBackend(mappings: [previousCaps])
      let session = MappingSession(backend: backend, targetKey: key)
      try session.apply()
      try backend.write(id: 1, mappings: [unrelated])
      XCTAssertEqual(backend.keyboards[0].mappings, [unrelated])
      try session.reconcile()
      XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, MappingPolicy.mapping(to: key)])
      try session.restore()
      XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, previousCaps])
    }
  }

  func testReconcileRecoversOriginalMappingWithoutRepeatedWrites() throws {
    let backend = MemoryBackend(mappings: [previousCaps])
    let session = MappingSession(backend: backend)
    try session.apply()
    try backend.write(id: 1, mappings: [previousCaps])
    try session.reconcile()
    XCTAssertEqual(backend.keyboards[0].mappings, [MappingPolicy.capsToF18])
    let writes = backend.writeCount
    try session.reconcile()
    XCTAssertEqual(backend.writeCount, writes)
  }

  func testReconcileRecoversReplacementServiceAfterTemporaryDisconnect() throws {
    let backend = MemoryBackend(mappings: [])
    let session = MappingSession(backend: backend)
    try session.apply()
    backend.keyboards = []
    try session.reconcile()
    XCTAssertTrue(session.isActive)
    backend.keyboards = [KeyboardState(id: 2, product: "Reconnected", mappings: [unrelated])]
    try session.reconcile()
    XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, MappingPolicy.capsToF18])
    try session.restore()
    XCTAssertEqual(backend.keyboards[0].mappings, [unrelated])
    XCTAssertFalse(session.isActive)
  }

  func testReconcileDoesNotApplyWhenStopped() throws {
    let backend = MemoryBackend(mappings: [])
    let session = MappingSession(backend: backend)
    try session.reconcile()
    XCTAssertEqual(backend.writeCount, 0)
    try session.apply()
    try session.restore()
    let writes = backend.writeCount
    try session.reconcile()
    XCTAssertEqual(backend.writeCount, writes)
    XCTAssertEqual(backend.keyboards[0].mappings, [])
  }

  func testReconcilePreservesExternalCapsChange() throws {
    let backend = MemoryBackend(mappings: [])
    let session = MappingSession(backend: backend)
    try session.apply()
    try backend.write(id: 1, mappings: [previousCaps, unrelated])
    try session.reconcile()
    XCTAssertEqual(backend.keyboards[0].mappings, [previousCaps, unrelated])
  }

  func testRestoreAfterResetBeforeRecovery() throws {
    let backend = MemoryBackend(mappings: [previousCaps])
    let session = MappingSession(backend: backend)
    try session.apply()
    try backend.write(id: 1, mappings: [unrelated])
    try session.restore()
    XCTAssertEqual(backend.keyboards[0].mappings, [unrelated, previousCaps])
    XCTAssertFalse(session.isActive)
  }
}

private final class MemoryBackend: KeyboardBackend {
  var keyboards: [KeyboardState]
  private(set) var writeCount = 0

  init(mappings: [KeyMapping]) {
    keyboards = [KeyboardState(id: 1, product: "Test Keyboard", mappings: mappings)]
  }

  func read() -> [KeyboardState] { keyboards }

  func write(id: UInt64, mappings: [KeyMapping]) throws {
    guard let index = keyboards.firstIndex(where: { $0.id == id }) else {
      throw KeyboardError.failure("Test keyboard missing")
    }
    writeCount += 1
    keyboards[index] = KeyboardState(id: id, product: keyboards[index].product, mappings: mappings)
  }
}
