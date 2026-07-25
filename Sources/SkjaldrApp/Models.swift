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

struct CompositionRowGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var itemIDs: [UUID]
    var caption: String = ""
}

struct OutputProfile: Codable, Equatable {
    var name = "Laudo padrão"
    var preferredWidth = 750
    var maximumWidth = 4000
    var maximumHeight = 12000
    var format: OutputFormat = .png
    var jpegQuality = 0.85
    var outerMargin = 12
    var horizontalSpacing = 12
    var verticalSpacing = 12
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
    var schemaVersion = 3
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var items: [CompositionItem] = []
    var rowGroups: [CompositionRowGroup] = []
    var layoutMode: LayoutMode = .automatic
    var outputProfile: OutputProfile = .report
    var automaticCropMode: AutomaticCropMode = .disabled

    mutating func normalizeOrder() {
        for index in items.indices {
            items[index].order = index
        }
        normalizeGroups()
        updatedAt = Date()
    }

    @discardableResult
    mutating func migrateIfNeeded() -> Bool {
        guard schemaVersion < 3 else { return false }
        if outputProfile.name == OutputProfile.report.name {
            if schemaVersion < 2, outputProfile.preferredWidth == 1800 {
                outputProfile.preferredWidth = OutputProfile.report.preferredWidth
            }
            if outputProfile.outerMargin == 32 {
                outputProfile.outerMargin = OutputProfile.report.outerMargin
            }
            if outputProfile.horizontalSpacing == 16 {
                outputProfile.horizontalSpacing = OutputProfile.report.horizontalSpacing
            }
            if outputProfile.verticalSpacing == 16 {
                outputProfile.verticalSpacing = OutputProfile.report.verticalSpacing
            }
        }
        schemaVersion = 3
        return true
    }

    private mutating func normalizeGroups() {
        let validIDs = Set(items.map(\.id))
        let orderByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.order) })
        var claimedIDs = Set<UUID>()
        rowGroups = rowGroups.compactMap { group in
            let uniqueIDs = Array(Set(group.itemIDs))
                .filter { validIDs.contains($0) && !claimedIDs.contains($0) }
                .sorted { (orderByID[$0] ?? 0) < (orderByID[$1] ?? 0) }
            guard uniqueIDs.count >= 2 else { return nil }
            claimedIDs.formUnion(uniqueIDs)
            var normalized = group
            normalized.itemIDs = uniqueIDs
            return normalized
        }
    }
}

extension CompositionState {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case createdAt
        case updatedAt
        case items
        case rowGroups
        case layoutMode
        case outputProfile
        case automaticCropMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        items = try container.decode([CompositionItem].self, forKey: .items)
        rowGroups = try container.decodeIfPresent([CompositionRowGroup].self, forKey: .rowGroups) ?? []
        layoutMode = try container.decode(LayoutMode.self, forKey: .layoutMode)
        outputProfile = try container.decode(OutputProfile.self, forKey: .outputProfile)
        automaticCropMode = try container.decode(AutomaticCropMode.self, forKey: .automaticCropMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(items, forKey: .items)
        try container.encode(rowGroups, forKey: .rowGroups)
        try container.encode(layoutMode, forKey: .layoutMode)
        try container.encode(outputProfile, forKey: .outputProfile)
        try container.encode(automaticCropMode, forKey: .automaticCropMode)
    }
}
