import CapsSwitchCore
import CoreGraphics
import Foundation

private let capsStateUpdateTimeout: TimeInterval = 0.5
private let capsStateCheckInterval: TimeInterval = 0.01

func runVerification() throws {
  let backend = SystemKeyboardBackend()
  let original = try backend.read()
  let originalLock = CapsLock.isEnabled
  let session = MappingSession(backend: backend)
  let hotkey = CapsHotkey(onPress: {})
  try hotkey.start()
  defer { hotkey.stop() }
  do {
    try session.apply()
    let applied = try backend.read()
    guard applied.count == original.count,
      applied.allSatisfy({ keyboard in
        guard let previous = original.first(where: { $0.id == keyboard.id }) else { return false }
        return keyboard.mappings == MappingPolicy.applying(to: previous.mappings)
      })
    else { throw KeyboardError.failure("Caps Lock 매핑 검증에 실패했습니다.") }
    print("Caps Lock → F18 적용·조회 성공: 키보드 \(applied.count)개")
    let externalBackend = SystemKeyboardBackend()
    for keyboard in applied {
      try externalBackend.write(
        id: keyboard.id,
        mappings: keyboard.mappings.filter {
          $0[MappingPolicy.sourceKey] != MappingPolicy.capsLockUsage
        })
    }
    let reset = try backend.read()
    guard reset.count == applied.count,
      reset.allSatisfy({ keyboard in
        keyboard.mappings.allSatisfy { $0[MappingPolicy.sourceKey] != MappingPolicy.capsLockUsage }
      })
    else { throw KeyboardError.failure("외부에서 초기화한 매핑을 조회하지 못했습니다.") }
    try session.reconcile()
    guard try externalBackend.read() == applied else {
      throw KeyboardError.failure("초기화한 키보드 매핑을 복구하지 못했습니다.")
    }
    print("별도 연결의 매핑 초기화 감지·복구 성공")
    try verifyCapsLock(!originalLock)
    try verifyCapsLock(originalLock)
    print("대문자 잠금 변경·복원 성공")
    try session.restore()
    guard try backend.read() == original else {
      throw KeyboardError.failure("키보드 매핑이 원래 상태와 일치하지 않습니다.")
    }
    print("원래 키보드 매핑 복원·조회 성공")
    print("Shift+F18 전역 단축키 등록·해제 성공")
  } catch {
    let primaryError = error
    do {
      try CapsLock.setEnabled(originalLock)
      try session.restore()
    } catch {
      throw KeyboardError.failure(
        "\(primaryError.localizedDescription)\n복원 실패: \(error.localizedDescription)")
    }
    throw primaryError
  }
}

private func verifyCapsLock(_ enabled: Bool) throws {
  try CapsLock.setEnabled(enabled)
  let deadline = Date().addingTimeInterval(capsStateUpdateTimeout)
  while CapsLock.isEnabled != enabled && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(capsStateCheckInterval))
  }
  guard CapsLock.isEnabled == enabled else {
    throw KeyboardError.failure("대문자 잠금 상태가 요청한 값으로 바뀌지 않았습니다.")
  }
}

func runShortcutVerification() throws {
  let backend = SystemShortcutBackend()
  let suite = "me.seokmin.caps-switch.shortcut-verification"
  guard let defaults = UserDefaults(suiteName: suite) else {
    throw KeyboardError.failure("검증용 복원 저장소를 만들지 못했습니다.")
  }
  let session = InputShortcutSession(backend: backend, defaults: defaults)
  try session.restore()
  let original = try backend.read()
  defer {
    if !session.hasPendingRestoration { defaults.removePersistentDomain(forName: suite) }
  }
  do {
    try session.apply(key: .f18)
    let external = SystemShortcutBackend()
    guard InputShortcutSession.matches(try external.read()["60"], key: .f18) else {
      throw KeyboardError.failure("별도 연결에서 F18 단축키를 확인하지 못했습니다.")
    }
    try session.restore()
    guard NSDictionary(dictionary: try external.read()).isEqual(to: original) else {
      throw KeyboardError.failure("복원한 시스템 단축키가 원래 설정과 다릅니다.")
    }
    print("이전 입력 소스 선택 → F18 적용·별도 조회·전체 단축키 복원 성공")
  } catch {
    let originalError = error
    do { try session.restore() } catch {
      throw KeyboardError.failure(
        "\(originalError.localizedDescription)\n복원 실패: \(error.localizedDescription)\n복원 정보: \(suite)"
      )
    }
    throw originalError
  }
}
