import XCTest

@testable import CapsSwitchCore

final class SwitchPulseTests: XCTestCase {
  func testPressPulsesOnceAndConsumesPhysicalReleaseAndRepeat() {
    var gate = SwitchPressGate()
    XCTAssertEqual(gate.handle(down: true, repeating: false, modified: false), .pulse)
    XCTAssertEqual(gate.handle(down: true, repeating: true, modified: false), .consume)
    XCTAssertEqual(gate.handle(down: true, repeating: false, modified: false), .consume)
    XCTAssertEqual(gate.handle(down: false, repeating: false, modified: true), .consume)
    XCTAssertEqual(gate.handle(down: true, repeating: false, modified: false), .pulse)
  }

  func testShiftCapsAndOtherModifiedShortcutsPassThrough() {
    var gate = SwitchPressGate()
    XCTAssertEqual(gate.handle(down: true, repeating: false, modified: true), .pass)
    XCTAssertEqual(gate.handle(down: true, repeating: true, modified: true), .pass)
    XCTAssertEqual(gate.handle(down: false, repeating: false, modified: false), .pass)
    XCTAssertEqual(gate.handle(down: true, repeating: true, modified: false), .consume)
    XCTAssertEqual(gate.handle(down: false, repeating: false, modified: false), .pass)
  }
}
