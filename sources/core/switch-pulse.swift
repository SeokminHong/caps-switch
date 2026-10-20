import ApplicationServices
import CoreGraphics
import Foundation

public struct SwitchPressGate {
  public enum Decision: Equatable { case pass, consume, pulse }
  private var held = false

  public init() {}

  public mutating func handle(down: Bool, repeating: Bool, modified: Bool) -> Decision {
    if !down {
      guard held else { return .pass }
      held = false
      return .consume
    }
    if held { return .consume }
    guard !modified else { return .pass }
    if repeating { return .consume }
    held = true
    return .pulse
  }
}

public final class SwitchPulse {
  public static var isTrusted: Bool { AXIsProcessTrusted() }

  public static func requestPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var gate = SwitchPressGate()
  private var key: FunctionKey = .f18
  private let onFailure: (Error) -> Void

  public init(onFailure: @escaping (Error) -> Void) { self.onFailure = onFailure }

  public func start(key: FunctionKey) throws {
    guard tap == nil else { return }
    guard Self.isTrusted else {
      throw KeyboardError.failure("즉시 전환을 사용하려면 손쉬운 사용 권한을 허용한 뒤 다시 시작해 주세요.")
    }
    self.key = key
    let mask =
      (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask,
        callback: { proxy, type, event, context in
          guard let context else { return Unmanaged.passUnretained(event) }
          return Unmanaged<SwitchPulse>.fromOpaque(context).takeUnretainedValue()
            .handle(proxy: proxy, type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()
      ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    else {
      throw KeyboardError.failure("즉시 전환 이벤트 처리를 시작하지 못했습니다. 손쉬운 사용 권한을 확인해 주세요.")
    }
    self.tap = tap
    self.source = source
    gate = SwitchPressGate()
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  public func reset() { gate = SwitchPressGate() }

  private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
    -> Unmanaged<CGEvent>?
  {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      reset()
      if Self.isTrusted, let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.onFailure(KeyboardError.failure("손쉬운 사용 권한이 해제되어 즉시 전환을 중지했습니다."))
        }
      }
      return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(key.keyCode) else {
      return Unmanaged.passUnretained(event)
    }
    let modified = !event.flags.intersection([
      .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]).isEmpty
    switch gate.handle(
      down: type == .keyDown,
      repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      modified: modified
    ) {
    case .pass: return Unmanaged.passUnretained(event)
    case .consume: return nil
    case .pulse:
      guard let down = event.copy(), let up = event.copy() else {
        reset()
        return Unmanaged.passUnretained(event)
      }
      down.type = .keyDown
      up.type = .keyUp
      down.tapPostEvent(proxy)
      up.tapPostEvent(proxy)
      return nil
    }
  }

  public func stop() {
    if let tap { CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    reset()
  }

  deinit { stop() }
}
