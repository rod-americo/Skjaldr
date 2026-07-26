import Foundation
import Testing
@testable import SkjaldrApp

@Suite("Upload de vídeo", .serialized)
struct VideoUploadTests {
    @Test("Configuração exige HTTPS e token")
    func configurationRequiresHTTPS() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("cloud-upload.json")
        try Data(
            #"{"baseURL":"http://odin.med.br","apiToken":"","uploadEnabled":true}"#
                .utf8
        ).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
        )
        #expect(throws: VideoUploadError.self) {
            try CloudUploadConfiguration.load(from: file)
        }
    }

    @Test("Configuração rejeita permissões para outros usuários")
    func configurationRejectsLoosePermissions() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(
            #"{"baseURL":"https://odin.med.br","apiToken":"secret","uploadEnabled":true}"#
                .utf8
        ).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: file.path
        )
        #expect(throws: VideoUploadError.self) {
            try CloudUploadConfiguration.load(from: file)
        }
    }

    @Test("Fila preserva idempotência e arquivo local")
    func queueItemRoundTrips() throws {
        let original = PendingVideoUpload(
            fileURL: URL(fileURLWithPath: "/tmp/video-laudo.mp4")
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode(
            [PendingVideoUpload].self,
            from: data
        )
        #expect(decoded == [original])
        #expect(decoded[0].idempotencyKey.count == 36)
        #expect(decoded[0].fileURL.path == "/tmp/video-laudo.mp4")
    }

    @Test("Conclusão remota permanece durável sem o derivado local")
    func completedQueueItemSurvivesMissingDerivative() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("video.mp4")
        try Data("video".utf8).write(to: source)
        var item = PendingVideoUpload(fileURL: source)
        item.optimizedFilePath = directory
            .appendingPathComponent(".skjaldr-upload-missing.mp4").path
        item.completedPublicURL = URL(
            string: "https://odin.med.br/123-456"
        )

        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode(
            [PendingVideoUpload].self,
            from: data
        )

        #expect(decoded[0].completedPublicURL == item.completedPublicURL)
        #expect(decoded[0].originalIdentity != nil)
    }

    @Test("Resposta remota decodifica URLs em snake case")
    func remoteResponseDecodes() throws {
        let data = Data(
            """
            {
              "id":"id-1",
              "short_code":"123-456",
              "public_url":"https://odin.med.br/123-456",
              "object_key":"videos/id-1.mp4",
              "status":"pending",
              "upload_url":"https://example.com/upload",
              "upload_headers":{"Content-Type":"video/mp4"}
            }
            """.utf8
        )
        let resource = try JSONDecoder().decode(
            RemoteVideoResource.self,
            from: data
        )
        #expect(resource.publicURL.absoluteString == "https://odin.med.br/123-456")
        #expect(resource.uploadURL?.host == "example.com")
    }

    @Test("Arquivo vazio é recusado antes da rede")
    func emptyFileIsRejected() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: VideoUploadError.self) {
            try await VideoUploadPreparation.prepare(file)
        }
    }

    @MainActor
    @Test("Fila não inicia trabalho enquanto a gravação está ativa")
    func queueStaysIdleDuringRecording() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SkjaldrUploadSuspension-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let queueURL = directory.appendingPathComponent("queue.json")
        let videoURL = directory.appendingPathComponent("video.mp4")
        try Data("arquivo de teste".utf8).write(to: videoURL)
        let store = VideoUploadStore(queueURL: queueURL)

        store.suspendForVideoRecording()
        store.enqueue(videoURL)
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.phase == .idle)
        let data = try Data(contentsOf: queueURL)
        let jobs = try JSONDecoder().decode(
            [PendingVideoUpload].self,
            from: data
        )
        #expect(jobs.count == 1)
        #expect(jobs[0].fileURL == videoURL)
    }
}
