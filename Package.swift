// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftyTesseractRTE",
  platforms: [.iOS(.v11), .macOS(.v10_13)],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "SwiftyTesseractRTE",
      targets: ["SwiftyTesseractRTE"]),
  ],
    dependencies: [.package(name: "SwiftyTesseract", url: "https://github.com/SwiftyTesseract/SwiftyTesseract.git", .branch("develop"))],
    
    targets: [
        .target(name: "SwiftyTesseractRTE", dependencies: [.byName(name: "SwiftyTesseract")], path: "SwiftyTesseractRTE/Classes", exclude: [String](), sources: nil, resources: nil, publicHeadersPath: nil, cSettings: nil, cxxSettings: nil, swiftSettings: nil, linkerSettings: nil)
  ]
)
