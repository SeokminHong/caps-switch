import Carbon

public enum FunctionKey: Int, CaseIterable {
  case f13 = 13
  case f14, f15, f16, f17, f18, f19, f20

  public var name: String { "F\(rawValue)" }

  public var hidUsage: UInt64 {
    let keyboardPage: UInt64 = 0x7_0000_0000
    let f13Usage: UInt64 = 0x68
    return keyboardPage | (f13Usage + UInt64(rawValue - Self.f13.rawValue))
  }

  public var keyCode: UInt32 {
    switch self {
    case .f13: return UInt32(kVK_F13)
    case .f14: return UInt32(kVK_F14)
    case .f15: return UInt32(kVK_F15)
    case .f16: return UInt32(kVK_F16)
    case .f17: return UInt32(kVK_F17)
    case .f18: return UInt32(kVK_F18)
    case .f19: return UInt32(kVK_F19)
    case .f20: return UInt32(kVK_F20)
    }
  }
}
