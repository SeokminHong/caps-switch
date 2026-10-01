// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CapsSwitch",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "caps-switch", targets: ["CapsSwitch"])],
  targets: [
    .target(
      name: "KeyboardBridge",
      path: "sources/keyboard-bridge",
      publicHeadersPath: "include",
      cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]
    ),
    .target(name: "CapsSwitchCore", dependencies: ["KeyboardBridge"], path: "sources/core"),
    .executableTarget(
      name: "CapsSwitch", dependencies: ["CapsSwitchCore"], path: "sources/app"
    ),
    .testTarget(name: "CapsSwitchTests", dependencies: ["CapsSwitchCore"], path: "tests"),
  ],
  swiftLanguageModes: [.v5]
)
