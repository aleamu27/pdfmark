// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDFMark",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PDFMark",
            path: "Sources/PDFMark"
        )
    ]
)
