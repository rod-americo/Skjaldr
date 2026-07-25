import Foundation

enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case automatic = "Automático"
    case grid = "Grade"
    case comparison = "Comparação"

    var id: String { rawValue }
}

enum AutomaticCropMode: String, Codable, CaseIterable, Identifiable {
    case disabled = "Não recortar"
    case uniformBorders = "Bordas uniformes"

    var id: String { rawValue }
}

enum OutputFormat: String, Codable, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"

    var id: String { rawValue }
}

struct NormalizedCrop: Codable, Equatable {
    var left: Double = 0
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0

    static let zero = NormalizedCrop()

    var isValid: Bool {
        left >= 0 && top >= 0 && right >= 0 && bottom >= 0 &&
        left + right < 0.95 && top + bottom < 0.95
    }
}

struct CompositionItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceURL: URL
    var originalWidth: Int
    var originalHeight: Int
    var crop: NormalizedCrop = .zero
    var rotation: Int = 0
    var caption: String = ""
    var isPrimary: Bool = false
    var order: Int = 0

    var croppedAspectRatio: Double {
        let width = Double(originalWidth) * (1 - crop.left - crop.right)
        let height = Double(originalHeight) * (1 - crop.top - crop.bottom)
        guard height > 0 else { return 1 }
        return max(0.05, width / height)
    }
}

struct OutputProfile: Codable, Equatable {
    var name = "Laudo padrão"
    var preferredWidth = 1800
    var maximumWidth = 4000
    var maximumHeight = 12000
    var format: OutputFormat = .png
    var jpegQuality = 0.85
    var outerMargin = 32
    var horizontalSpacing = 16
    var verticalSpacing = 16
    var backgroundHex = "#FFFFFF"
    var allowUpscaling = false

    static let report = OutputProfile()

    static let highResolution = OutputProfile(
        name: "Alta resolução",
        preferredWidth: 2480,
        maximumWidth: 4000,
        maximumHeight: 12000,
        format: .png,
        jpegQuality: 0.85,
        outerMargin: 40,
        horizontalSpacing: 20,
        verticalSpacing: 20,
        backgroundHex: "#FFFFFF",
        allowUpscaling: false
    )

    static let compact = OutputProfile(
        name: "Imagem compacta",
        preferredWidth: 1200,
        maximumWidth: 4000,
        maximumHeight: 12000,
        format: .jpeg,
        jpegQuality: 0.85,
        outerMargin: 24,
        horizontalSpacing: 12,
        verticalSpacing: 12,
        backgroundHex: "#FFFFFF",
        allowUpscaling: false
    )
}

struct CompositionState: Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var items: [CompositionItem] = []
    var layoutMode: LayoutMode = .automatic
    var outputProfile: OutputProfile = .report
    var automaticCropMode: AutomaticCropMode = .disabled

    mutating func normalizeOrder() {
        for index in items.indices {
            items[index].order = index
        }
        updatedAt = Date()
    }
}
