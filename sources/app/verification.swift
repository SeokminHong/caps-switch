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
