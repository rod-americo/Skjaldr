import Foundation

struct SessionPersistence {
    let rootDirectory: URL

    var sourcesDirectory: URL { rootDirectory.appendingPathComponent("Sources", isDirectory: true) }
    var temporaryDirectory: URL { rootDirectory.appendingPathComponent("Temporarios", isDirectory: true) }
    private var stateURL: URL { rootDirectory.appendingPathComponent("sessao.json") }

    static func live() -> SessionPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SessionPersistence(rootDirectory: base.appendingPathComponent("Skjaldr", isDirectory: true))
    }

    func load() -> CompositionState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder.project.decode(CompositionState.self, from: data)
    }

    func save(_ state: CompositionState) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.pretty.encode(state)
        try data.write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    func removeSource(at url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == sourcesDirectory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    func reset() throws {
        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.removeItem(at: rootDirectory)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var project: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
