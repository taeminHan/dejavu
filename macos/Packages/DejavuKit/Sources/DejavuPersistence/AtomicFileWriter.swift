import Foundation

public protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to destinationURL: URL) throws
}
public struct FoundationAtomicFileWriter: AtomicFileWriting {
    public init() {}

    public func write(_ data: Data, to destinationURL: URL) throws {
        // Foundation's atomic option writes a sibling temporary file before
        // replacing the destination, so readers never observe partial JSON.
        try data.write(to: destinationURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
    }
}

enum LocalDataDirectory {
    static func prepare(_ directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }
}
