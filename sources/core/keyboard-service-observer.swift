import Foundation
import IOKit

public final class KeyboardServiceObserver {
  private let onChange: () -> Void
  private var port: IONotificationPortRef?
  private var iterators: [io_iterator_t] = []

  public init(onChange: @escaping () -> Void) { self.onChange = onChange }

  public func start() throws {
    guard port == nil else { return }
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
      throw KeyboardError.failure("키보드 연결 알림을 등록하지 못했습니다.")
    }
    self.port = port
    let context = Unmanaged.passUnretained(self).toOpaque()
    for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
      var iterator: io_iterator_t = 0
      let result = IOServiceAddMatchingNotification(
        port, notification, IOServiceMatching("IOHIDEventService"),
        { context, iterator in
          guard let context else { return }
          let observer = Unmanaged<KeyboardServiceObserver>.fromOpaque(context)
            .takeUnretainedValue()
          observer.drain(iterator)
          observer.onChange()
        }, context, &iterator
      )
      guard result == KERN_SUCCESS else {
        stop()
        throw KeyboardError.failure("키보드 연결 알림을 등록하지 못했습니다. 코드: \(result)")
      }
      iterators.append(iterator)
      drain(iterator)
    }
    if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
  }

  private func drain(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
  }

  public func stop() {
    if let port {
      if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      }
      for iterator in iterators { IOObjectRelease(iterator) }
      IONotificationPortDestroy(port)
    }
    iterators.removeAll()
    port = nil
  }

  deinit { stop() }
}
