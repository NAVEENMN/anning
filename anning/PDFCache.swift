import Foundation

enum PDFCache {
    static func cacheDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dir = appSupport
            .appendingPathComponent("anning", isDirectory: true)
            .appendingPathComponent("pdfs", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func destinationURL(paperID: UUID) throws -> URL {
        let dir = try cacheDirectory()
        return dir.appendingPathComponent("\(paperID.uuidString).pdf")
    }

    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func fileExists(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
