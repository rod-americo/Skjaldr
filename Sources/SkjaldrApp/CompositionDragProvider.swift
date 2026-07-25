import AppKit
import Foundation

struct PreparedCompositionDrag {
    let provider: NSItemProvider
    let fileURL: URL
}

/// Prepara o arraste como URL de arquivo, sem anunciar uma representação de
/// imagem concorrente. Isso reproduz o comportamento de arrastar um PNG salvo
/// pelo Finder para editores HTML que aceitam upload por drop.
struct CompositionDragProvider {
    private let filePrefix = "composicao-arrastada-"

    func prepare(pngData: Data, temporaryDirectory: URL) throws -> PreparedCompositionDrag {
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        removeExpiredFiles(in: temporaryDirectory)

        let fileURL = temporaryDirectory
            .appendingPathComponent("\(filePrefix)\(UUID().uuidString)")
            .appendingPathExtension("png")
        try pngData.write(to: fileURL, options: [.atomic, .completeFileProtection])

        // NSURL publica public.file-url/public.url, como um arquivo do Finder.
        // Não registrar public.png aqui é intencional: alguns editores escolhem
        // os bytes de imagem e ignoram o caminho de upload que funciona via drop.
        let provider = NSItemProvider(object: fileURL as NSURL)
        provider.suggestedName = "composicao.png"
        return PreparedCompositionDrag(provider: provider, fileURL: fileURL)
    }

    private func removeExpiredFiles(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files where file.lastPathComponent.hasPrefix(filePrefix) {
            let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let date, date < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
