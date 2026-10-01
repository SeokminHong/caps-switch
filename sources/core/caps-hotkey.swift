import Carbon
import CoreGraphics
import Foundation
import KeyboardBridge

public enum CapsLock {
  public static var isEnabled: Bool {
    CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
  }

  public static func setEnabled(_ enabled: Bool) throws {
    let result = CKSetCapsLock(enabled)
    guard result == 0 else {
      throw KeyboardError.failure("대문자 잠금을 변경하지 못했습니다. IOKit 코드: \(result)")
    }
  }

  public static func toggle() throws { try setEnabled(!isEnabled) }
}

public final class CapsHotkey {
  private static let signature: OSType = 0x4350_5357
  private static let hotkeyId: UInt32 = 1
  private var hotkey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let onPress: () -> Void

  public init(onPress: @escaping () -> Void) { self.onPress = onPress }

  public func start(key: FunctionKey = .f18) throws {
    guard hotkey == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
    )
    let context = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
        )
        guard status == noErr, identifier.signature == CapsHotkey.signature,
          identifier.id == CapsHotkey.hotkeyId
        else { return OSStatus(eventNotHandledErr) }
        Unmanaged<CapsHotkey>.fromOpaque(context).takeUnretainedValue().onPress()
        return noErr
      }, 1, &eventType, context, &handler
    )
    guard handlerStatus == noErr else {
      throw KeyboardError.failure("단축키 처리기를 등록하지 못했습니다. 코드: \(handlerStatus)")
    }
    let status = RegisterEventHotKey(
      key.keyCode, UInt32(shiftKey),
      EventHotKeyID(signature: Self.signature, id: Self.hotkeyId),
      GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotkey
    )
    guard status == noErr else {
      stop()
      throw KeyboardError.failure("Shift+\(key.name)을 등록하지 못했습니다. 코드: \(status)")
    }
  }

  public func stop() {
    if let hotkey { UnregisterEventHotKey(hotkey) }
    if let handler { RemoveEventHandler(handler) }
    hotkey = nil
    handler = nil
  }

  deinit { stop() }
}
