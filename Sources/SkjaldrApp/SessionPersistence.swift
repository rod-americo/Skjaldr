import Foundation

struct SessionPersistence {
    static let primaryCompositionID = UUID(
        uuidString: "8F56D086-E6E5-42F4-9364-672CBFD49A31"
    )!

    let rootDirectory: URL

    var sourcesDirectory: URL { rootDirectory.appendingPathComponent("Sources", isDirectory: true) }
    var temporaryDirectory: URL { rootDirectory.appendingPathComponent("Temporarios", isDirectory: true) }
    private var stateURL: URL { rootDirectory.appendingPathComponent("sessao.json") }

    static func live() -> SessionPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SessionPersistence(rootDirectory: base.appendingPathComponent("Skjaldr", isDirectory: true))
    }

    static func live(compositionID: UUID) -> SessionPersistence {
        let primary = live()
        guard compositionID != primaryCompositionID else {
            return primary
        }
        return SessionPersistence(
            rootDirectory: primary.rootDirectory
                .appendingPathComponent("Composicoes", isDirectory: true)
                .appendingPathComponent(compositionID.uuidString, isDirectory: true)
        )
    }

    func load() -> CompositionState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder.project.decode(CompositionState.self, from: data)
    }

    func startFreshPreservingPreferences() -> CompositionState {
        var previous = load()
        _ = previous?.migrateIfNeeded()

        var fresh = CompositionState()
        if let previous {
            fresh.layoutMode = previous.layoutMode
            fresh.outputProfile = previous.outputProfile
            fresh.automaticCropMode = previous.automaticCropMode
        }

        removeIfPresent(stateURL)
        removeIfPresent(sourcesDirectory)
        removeIfPresent(temporaryDirectory)
        try? save(fresh)
        return fresh
    }

    static func removeSecondaryCompositions() {
        let directory = live().rootDirectory
            .appendingPathComponent("Composicoes", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try? FileManager.default.removeItem(at: directory)
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

    private func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
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
