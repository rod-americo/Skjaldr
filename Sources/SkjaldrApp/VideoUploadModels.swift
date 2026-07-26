import Foundation

enum VideoUploadPhase: Equatable {
    case idle
    case preparing
    case uploading
    case confirming
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: "Aguardando"
        case .preparing: "Preparando vídeo…"
        case .uploading: "Enviando vídeo…"
        case .confirming: "Confirmando upload…"
        case .completed: "Link criado"
        case .failed: "Upload não concluído"
        }
    }
}

struct CloudUploadConfiguration: Decodable {
    let baseURL: URL
    let apiToken: String
    let uploadEnabled: Bool

    static var defaultURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Skjaldr/cloud-upload.json")
    }

    static func load(from url: URL = defaultURL) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        if let permissions = attributes[.posixPermissions] as? NSNumber,
           permissions.intValue & 0o077 != 0
        {
            throw VideoUploadError.insecureConfiguration
        }
        let value = try JSONDecoder().decode(
            Self.self,
            from: Data(contentsOf: url)
        )
        guard value.baseURL.scheme == "https",
              !value.apiToken.isEmpty
        else {
            throw VideoUploadError.invalidConfiguration
        }
        return value
    }
}

struct PendingVideoUpload: Codable, Identifiable, Equatable {
    let id: UUID
    let filePath: String
    let idempotencyKey: String
    var attempts: Int
    var optimizedFilePath: String?

    init(fileURL: URL) {
        id = UUID()
        filePath = fileURL.path
        idempotencyKey = UUID().uuidString.lowercased()
        attempts = 0
        optimizedFilePath = nil
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var uploadFileURL: URL {
        optimizedFilePath.map(URL.init(fileURLWithPath:)) ?? fileURL
    }
}

struct CreateVideoRequest: Encodable {
    let idempotencyKey: String
    let contentType = "video/mp4"
    let sizeBytes: Int64
    let durationSeconds: Double
    let sha256: String
}

struct RemoteVideoResource: Decodable {
    let id: String
    let shortCode: String
    let publicURL: URL
    let objectKey: String
    let status: String
    let uploadURL: URL?
    let uploadHeaders: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case shortCode = "short_code"
        case publicURL = "public_url"
        case objectKey = "object_key"
        case status
        case uploadURL = "upload_url"
        case uploadHeaders = "upload_headers"
    }
}

enum VideoUploadError: LocalizedError {
    case notConfigured
    case insecureConfiguration
    case invalidConfiguration
    case invalidFile
    case fileTooLarge
    case invalidVideo
    case videoOptimizationFailed
    case invalidResponse
    case remote(String)
    case clipboard

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "O upload não está configurado. Execute setup-cloudflare.sh."
        case .insecureConfiguration:
            "A configuração de upload possui permissões de arquivo inseguras."
        case .invalidConfiguration:
            "A configuração de upload é inválida."
        case .invalidFile:
            "O arquivo local não existe ou está vazio."
        case .fileTooLarge:
            "O vídeo excede o limite de 1 GiB."
        case .invalidVideo:
            "O arquivo MP4 não pôde ser validado para reprodução."
        case .videoOptimizationFailed:
            "Não foi possível preparar uma cópia otimizada do vídeo."
        case .invalidResponse:
            "O serviço de upload retornou uma resposta inválida."
        case let .remote(message):
            "O serviço de upload recusou a operação: \(message)"
        case .clipboard:
            "O link foi criado, mas não pôde ser copiado automaticamente."
        }
    }
}
