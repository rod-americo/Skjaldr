import AppKit
import Foundation

/// Detecta somente faixas externas quase uniformes. O limite de 20% por lado e a
/// tolerância cromática baixa tornam o comportamento deliberadamente conservador.
struct UniformBorderCropDetector {
    private let colorTolerance = 6
    private let requiredUniformity = 0.995
    private let maximumFraction = 0.20

    func detect(in image: NSImage) -> NormalizedCrop {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              bitmap.pixelsWide > 20,
              bitmap.pixelsHigh > 20
        else {
            return .zero
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard let leftReference = bitmap.colorAt(x: 0, y: height / 2)?.usingColorSpace(.deviceRGB),
              let rightReference = bitmap.colorAt(x: width - 1, y: height / 2)?.usingColorSpace(.deviceRGB),
              let bottomReference = bitmap.colorAt(x: width / 2, y: 0)?.usingColorSpace(.deviceRGB),
              let topReference = bitmap.colorAt(x: width / 2, y: height - 1)?.usingColorSpace(.deviceRGB)
        else {
            return .zero
        }
        let maxX = Int(Double(width) * maximumFraction)
        let maxY = Int(Double(height) * maximumFraction)

        var left = 0
        while left < maxX && columnIsUniform(left, bitmap: bitmap, reference: leftReference) {
            left += 1
        }
        var right = 0
        while right < maxX && columnIsUniform(width - 1 - right, bitmap: bitmap, reference: rightReference) {
            right += 1
        }
        var bottom = 0
        while bottom < maxY && rowIsUniform(bottom, bitmap: bitmap, reference: bottomReference) {
            bottom += 1
        }
        var top = 0
        while top < maxY && rowIsUniform(height - 1 - top, bitmap: bitmap, reference: topReference) {
            top += 1
        }

        // Uma borda de um único pixel costuma ser antialiasing, não uma barra útil.
        let minimum = 2
        let crop = NormalizedCrop(
            left: left >= minimum ? Double(left) / Double(width) : 0,
            top: top >= minimum ? Double(top) / Double(height) : 0,
            right: right >= minimum ? Double(right) / Double(width) : 0,
            bottom: bottom >= minimum ? Double(bottom) / Double(height) : 0
        )
        return crop.isValid ? crop : .zero
    }

    private func columnIsUniform(
        _ x: Int,
        bitmap: NSBitmapImageRep,
        reference: NSColor
    ) -> Bool {
        let step = max(1, bitmap.pixelsHigh / 400)
        var matches = 0
        var samples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            samples += 1
            if isSimilar(bitmap.colorAt(x: x, y: y), to: reference) {
                matches += 1
            }
        }
        return samples > 0 && Double(matches) / Double(samples) >= requiredUniformity
    }

    private func rowIsUniform(
        _ y: Int,
        bitmap: NSBitmapImageRep,
        reference: NSColor
    ) -> Bool {
        let step = max(1, bitmap.pixelsWide / 400)
        var matches = 0
        var samples = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
            samples += 1
            if isSimilar(bitmap.colorAt(x: x, y: y), to: reference) {
                matches += 1
            }
        }
        return samples > 0 && Double(matches) / Double(samples) >= requiredUniformity
    }

    private func isSimilar(_ color: NSColor?, to reference: NSColor) -> Bool {
        guard let rgb = color?.usingColorSpace(.deviceRGB) else { return false }
        let scale = 255.0
        return abs(Int(rgb.redComponent * scale) - Int(reference.redComponent * scale)) <= colorTolerance &&
            abs(Int(rgb.greenComponent * scale) - Int(reference.greenComponent * scale)) <= colorTolerance &&
            abs(Int(rgb.blueComponent * scale) - Int(reference.blueComponent * scale)) <= colorTolerance &&
            abs(Int(rgb.alphaComponent * scale) - Int(reference.alphaComponent * scale)) <= colorTolerance
    }
}
