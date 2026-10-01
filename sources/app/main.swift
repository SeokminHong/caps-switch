import CapsSwitchCore
import Foundation

do {
  let keyboards = try SystemKeyboardBackend().read()
  let hotkey = CapsHotkey(onPress: {})
  try hotkey.start()
  hotkey.stop()
  print("키보드 \(keyboards.count)개 조회, Shift+F18 등록·해제 성공")
  for keyboard in keyboards {
    print("\(keyboard.product): \(keyboard.id), 매핑 \(keyboard.mappings.count)개")
  }
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
