import Foundation

public protocol ShortcutBackend {
  func read() throws -> [String: Any]
  func write(_ shortcuts: [String: Any]) throws
  func activate() throws
}

public final class SystemShortcutBackend: ShortcutBackend {
  private let domain = "com.apple.symbolichotkeys" as CFString
  private let preference = "AppleSymbolicHotKeys" as CFString
  public init() {}

  public func read() throws -> [String: Any] {
    guard CFPreferencesAppSynchronize(domain) else {
      throw KeyboardError.failure("입력 소스 단축키를 조회하지 못했습니다.")
    }
    guard let raw = CFPreferencesCopyAppValue(preference, domain) else { return [:] }
    guard let shortcuts = raw as? [String: Any] else {
      throw KeyboardError.failure("입력 소스 단축키 설정 형식을 확인할 수 없습니다.")
    }
    return shortcuts
  }

  public func write(_ shortcuts: [String: Any]) throws {
    CFPreferencesSetAppValue(preference, shortcuts as CFDictionary, domain)
    guard CFPreferencesAppSynchronize(domain) else {
      throw KeyboardError.failure("입력 소스 단축키를 저장하지 못했습니다.")
    }
  }

  public func activate() throws {
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath:
        "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
    )
    process.arguments = ["-u", "-virtualSession"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + 5) == .success else {
      process.terminate()
      throw KeyboardError.failure("입력 소스 단축키 반영 시간이 초과되었습니다. 다시 시도해 주세요.")
    }
    guard process.terminationStatus == 0 else {
      throw KeyboardError.failure("입력 소스 단축키를 반영하지 못했습니다. 코드: \(process.terminationStatus)")
    }
  }
}

public final class InputShortcutSession {
  private let backend: ShortcutBackend
  private let defaults: UserDefaults
  private let journalKey = "inputShortcutRestoration"
  private let previousSource = "60"

  public init(
    backend: ShortcutBackend = SystemShortcutBackend(), defaults: UserDefaults = .standard
  ) {
    self.backend = backend
    self.defaults = defaults
  }

  public var hasPendingRestoration: Bool { defaults.dictionary(forKey: journalKey) != nil }

  public func isConfigured(for key: FunctionKey) -> Bool {
    guard let shortcuts = try? backend.read() else { return false }
    return Self.matches(shortcuts[previousSource], key: key)
  }

  public static func matches(_ raw: Any?, key: FunctionKey) -> Bool {
    guard let entry = raw as? [String: Any], entry["enabled"] as? Bool == true,
      let value = entry["value"] as? [String: Any],
      let parameters = value["parameters"] as? [NSNumber], parameters.count == 3
    else { return false }
    return parameters[1].uint32Value == key.keyCode && parameters[2].intValue == 0
  }

  private func equal(_ left: Any?, _ right: Any?) -> Bool {
    guard let left else { return right == nil }
    guard let right else { return false }
    return NSDictionary(dictionary: ["entry": left]).isEqual(to: ["entry": right])
  }

  public func availableKey(preferred: FunctionKey) throws -> FunctionKey {
    let shortcuts = try backend.read()
    let candidates = [preferred] + FunctionKey.allCases.filter { $0 != preferred }
    guard
      let key = candidates.first(where: { key in
        !shortcuts.contains { id, entry in id != previousSource && Self.matches(entry, key: key) }
      })
    else {
      throw KeyboardError.failure("한영 전환에 사용할 수 있는 F13~F20 키가 없습니다. 다른 단축키 앱과의 충돌을 확인해 주세요.")
    }
    return key
  }

  public func apply(key: FunctionKey) throws {
    if let journal = defaults.dictionary(forKey: journalKey), journal["restoring"] as? Bool == true
    {
      try restore()
    }
    var shortcuts = try backend.read()
    for (id, entry) in shortcuts where id != previousSource {
      if Self.matches(entry, key: key) {
        throw KeyboardError.failure("\(key.name)은 다른 macOS 단축키에서 사용 중입니다. 다른 키를 선택해 주세요.")
      }
    }
    let managed: [String: Any] = [
      "enabled": true,
      "value": ["type": "standard", "parameters": [65535, Int(key.keyCode), 0]],
    ]
    var journal = defaults.dictionary(forKey: journalKey)
    if journal == nil || !equal(shortcuts[previousSource], journal?["managed"]) {
      journal = ["managed": managed]
      journal?["original"] = shortcuts[previousSource]
    }
    journal?["managed"] = managed
    defaults.set(journal, forKey: journalKey)
    guard defaults.synchronize() else {
      throw KeyboardError.failure("원래 단축키 복원 정보를 저장하지 못했습니다.")
    }
    shortcuts[previousSource] = managed
    try backend.write(shortcuts)
    try backend.activate()
    guard isConfigured(for: key) else {
      throw KeyboardError.failure("입력 소스 단축키 저장 결과를 확인하지 못했습니다.")
    }
  }

  public func restore() throws {
    guard var journal = defaults.dictionary(forKey: journalKey) else { return }
    var shortcuts = try backend.read()
    if equal(shortcuts[previousSource], journal["managed"]) {
      journal["restoring"] = true
      defaults.set(journal, forKey: journalKey)
      guard defaults.synchronize() else {
        throw KeyboardError.failure("단축키 복원 상태를 저장하지 못했습니다.")
      }
      shortcuts[previousSource] = journal["original"]
      try backend.write(shortcuts)
      try backend.activate()
      guard equal(try backend.read()[previousSource], journal["original"]) else {
        throw KeyboardError.failure("입력 소스 단축키 복원 결과를 확인하지 못했습니다.")
      }
    } else if journal["restoring"] as? Bool == true,
      equal(shortcuts[previousSource], journal["original"])
    {
      try backend.activate()
    }
    defaults.removeObject(forKey: journalKey)
    _ = defaults.synchronize()
  }
}
