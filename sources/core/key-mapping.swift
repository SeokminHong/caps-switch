import Foundation
import KeyboardBridge

public typealias KeyMapping = [String: UInt64]

public enum MappingPolicy {
  public static let sourceKey = "HIDKeyboardModifierMappingSrc"
  public static let destinationKey = "HIDKeyboardModifierMappingDst"
  public static let capsLockUsage: UInt64 = 0x7_0000_0039
  public static let f18Usage: UInt64 = 0x7_0000_006D
  public static let capsToF18: KeyMapping = [sourceKey: capsLockUsage, destinationKey: f18Usage]

  public static func mapping(to key: FunctionKey) -> KeyMapping {
    [sourceKey: capsLockUsage, destinationKey: key.hidUsage]
  }

  public static func applying(to mappings: [KeyMapping], key: FunctionKey = .f18) -> [KeyMapping] {
    mappings.filter { $0[sourceKey] != capsLockUsage } + [mapping(to: key)]
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

public final class SystemKeyboardBackend: KeyboardBackend {
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
  public let targetKey: FunctionKey
  public private(set) var isActive = false
  public var hasPendingRestoration: Bool { !originals.isEmpty }

  public init(backend: any KeyboardBackend = SystemKeyboardBackend(), targetKey: FunctionKey = .f18)
  {
    self.backend = backend
    self.targetKey = targetKey
  }

  public func apply() throws {
    guard isActive || !hasPendingRestoration else {
      throw KeyboardError.failure("이전 매핑을 먼저 복원해 주세요.")
    }
    let keyboards = try backend.read()
    isActive = true
    var failures: [String] = []
    for keyboard in keyboards {
      if originals[keyboard.id] == nil {
        originals[keyboard.id] = capsMappings(in: keyboard.mappings)
      }
      do {
        try backend.write(
          id: keyboard.id, mappings: MappingPolicy.applying(to: keyboard.mappings, key: targetKey))
      } catch {
        failures.append("\(keyboard.product): \(error.localizedDescription)")
      }
    }
    if !failures.isEmpty { throw KeyboardError.failure(failures.joined(separator: "\n")) }
  }

  public func restore() throws {
    isActive = false
    guard hasPendingRestoration else { return }
    let keyboards = try backend.read()
    var failures: [String] = []
    for keyboard in keyboards {
      guard let original = originals[keyboard.id] else { continue }
      let capsMappings = capsMappings(in: keyboard.mappings)
      guard
        capsMappings.isEmpty || capsMappings == [MappingPolicy.mapping(to: targetKey)]
          || capsMappings == original
      else {
        originals.removeValue(forKey: keyboard.id)
        continue
      }
      do {
        let restored = MappingPolicy.restoring(current: keyboard.mappings, original: original)
        if restored != keyboard.mappings {
          try backend.write(id: keyboard.id, mappings: restored)
        }
        originals.removeValue(forKey: keyboard.id)
      } catch {
        failures.append("\(keyboard.product): \(error.localizedDescription)")
      }
    }
    let connectedIds = Set(keyboards.map(\.id))
    originals = originals.filter { connectedIds.contains($0.key) }
    if !failures.isEmpty { throw KeyboardError.failure(failures.joined(separator: "\n")) }
  }

  public func reconcile() throws {
    guard isActive else { return }
    let keyboards = try backend.read()
    guard !keyboards.isEmpty else { return }
    let connectedIds = Set(keyboards.map(\.id))
    originals = originals.filter { connectedIds.contains($0.key) }
    var failures: [String] = []
    for keyboard in keyboards {
      let capsMappings = capsMappings(in: keyboard.mappings)
      if let original = originals[keyboard.id] {
        guard capsMappings.isEmpty || capsMappings == original else { continue }
      } else {
        originals[keyboard.id] = capsMappings
      }
      if capsMappings == [MappingPolicy.mapping(to: targetKey)] { continue }
      do {
        try backend.write(
          id: keyboard.id, mappings: MappingPolicy.applying(to: keyboard.mappings, key: targetKey))
      } catch {
        failures.append("\(keyboard.product): \(error.localizedDescription)")
      }
    }
    if !failures.isEmpty { throw KeyboardError.failure(failures.joined(separator: "\n")) }
  }

  private func capsMappings(in mappings: [KeyMapping]) -> [KeyMapping] {
    mappings.filter { $0[MappingPolicy.sourceKey] == MappingPolicy.capsLockUsage }
  }
}
