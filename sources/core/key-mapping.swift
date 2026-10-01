import Foundation
import KeyboardBridge

public typealias KeyMapping = [String: UInt64]

public enum MappingPolicy {
  public static let sourceKey = "HIDKeyboardModifierMappingSrc"
  public static let destinationKey = "HIDKeyboardModifierMappingDst"
  public static let capsLockUsage: UInt64 = 0x7_0000_0039
  public static let f18Usage: UInt64 = 0x7_0000_006D
  public static let capsToF18: KeyMapping = [sourceKey: capsLockUsage, destinationKey: f18Usage]

  public static func applying(to mappings: [KeyMapping]) -> [KeyMapping] {
    mappings.filter { $0[sourceKey] != capsLockUsage } + [capsToF18]
  }

  public static func restoring(current: [KeyMapping], original: [KeyMapping]) -> [KeyMapping] {
    current.filter { $0[sourceKey] != capsLockUsage }
      + original.filter { $0[sourceKey] == capsLockUsage }
  }
}

public struct KeyboardState: Equatable {
  public let id: UInt64
  public let product: String
  public let mappings: [KeyMapping]

  public init(id: UInt64, product: String, mappings: [KeyMapping]) {
    self.id = id
    self.product = product
    self.mappings = mappings
  }
}

public enum KeyboardError: LocalizedError {
  case failure(String)

  public var errorDescription: String? {
    switch self {
    case .failure(let message): return message
    }
  }
}

public protocol KeyboardBackend {
  func read() throws -> [KeyboardState]
  func write(id: UInt64, mappings: [KeyMapping]) throws
}

public struct SystemKeyboardBackend: KeyboardBackend {
  public init() {}

  public func read() throws -> [KeyboardState] {
    guard let array = CKCopyKeyboards() else {
      throw KeyboardError.failure("키보드 서비스를 조회하지 못했습니다.")
    }
    guard let records = array as? [[String: Any]] else {
      throw KeyboardError.failure("키보드 서비스의 응답 형식을 확인할 수 없습니다.")
    }
    return try records.map { record in
      guard let id = record["id"] as? NSNumber,
        let product = record["product"] as? String,
        let rawMappings = record["mapping"] as? [[String: NSNumber]]
      else { throw KeyboardError.failure("키보드 매핑의 응답 형식을 확인할 수 없습니다.") }
      return KeyboardState(
        id: id.uint64Value, product: product,
        mappings: rawMappings.map { $0.mapValues(\.uint64Value) }
      )
    }
  }

  public func write(id: UInt64, mappings: [KeyMapping]) throws {
    let array = mappings.map { $0.mapValues { NSNumber(value: $0) } } as NSArray
    guard CKSetMapping(id, array as CFArray),
      try read().first(where: { $0.id == id })?.mappings == mappings
    else { throw KeyboardError.failure("키보드 \(id)의 매핑을 적용하지 못했습니다.") }
  }
}

public final class MappingSession {
  private let backend: any KeyboardBackend
  private var originals: [UInt64: [KeyMapping]] = [:]
  public var isActive: Bool { !originals.isEmpty }

  public init(backend: any KeyboardBackend = SystemKeyboardBackend()) {
    self.backend = backend
  }

  public func apply() throws {
    let keyboards = try backend.read()
    guard !keyboards.isEmpty else { throw KeyboardError.failure("연결된 키보드를 찾지 못했습니다.") }
    for keyboard in keyboards {
      if originals[keyboard.id] == nil { originals[keyboard.id] = keyboard.mappings }
      try backend.write(id: keyboard.id, mappings: MappingPolicy.applying(to: keyboard.mappings))
    }
  }

  public func restore() throws {
    let keyboards = try backend.read()
    for keyboard in keyboards {
      guard let original = originals[keyboard.id] else { continue }
      let capsMappings = keyboard.mappings.filter {
        $0[MappingPolicy.sourceKey] == MappingPolicy.capsLockUsage
      }
      guard capsMappings == [MappingPolicy.capsToF18] || keyboard.mappings == original else {
        throw KeyboardError.failure("다른 앱이 Caps Lock 매핑을 변경했습니다. 해당 매핑은 유지합니다.")
      }
      try backend.write(
        id: keyboard.id,
        mappings: MappingPolicy.restoring(current: keyboard.mappings, original: original)
      )
      originals.removeValue(forKey: keyboard.id)
    }
    let connectedIds = Set(keyboards.map(\.id))
    originals = originals.filter { connectedIds.contains($0.key) }
  }
}
