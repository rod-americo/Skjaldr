import CoreGraphics
import Foundation
import Testing
@testable import SkjaldrApp

@Suite("Captura de vídeo")
struct VideoCaptureTests {
    @Test("Presets preservam exatamente a proporção 19,5:9")
    func phonePresetsUseExactAspectRatio() {
        let portrait = PhoneVideoPreset.portrait
        let landscape = PhoneVideoPreset.landscape

        #expect(abs(portrait.aspectRatio - CGFloat(6.0 / 13.0)) < 0.000_001)
        #expect(abs(landscape.aspectRatio - CGFloat(13.0 / 6.0)) < 0.000_001)
        #expect(
            portrait.outputSize.width / portrait.outputSize.height
                == portrait.aspectRatio
        )
        #expect(
            landscape.outputSize.width / landscape.outputSize.height
                == landscape.aspectRatio
        )
        #expect(Int(portrait.outputSize.width).isMultiple(of: 2))
        #expect(Int(portrait.outputSize.height).isMultiple(of: 2))
        #expect(Int(landscape.outputSize.width).isMultiple(of: 2))
        #expect(Int(landscape.outputSize.height).isMultiple(of: 2))
    }

    @Test("Seleção mantém a proporção e respeita os limites da tela")
    func selectionIsConstrainedToScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let region = VideoRegionGeometry.region(
            from: CGPoint(x: 1200, y: 700),
            to: CGPoint(x: 1600, y: 1000),
            aspectRatio: PhoneVideoPreset.landscape.aspectRatio,
            inside: bounds
        )

        #expect(bounds.contains(region))
        #expect(
            abs(
                region.width / region.height
                    - PhoneVideoPreset.landscape.aspectRatio
            ) < 0.01
        )
    }

    @Test("Seleção funciona em todas as direções do arraste")
    func selectionSupportsEveryDragDirection() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 1200)
        let anchor = CGPoint(x: 600, y: 600)
        let pointers = [
            CGPoint(x: 900, y: 1000),
            CGPoint(x: 300, y: 1000),
            CGPoint(x: 900, y: 200),
            CGPoint(x: 300, y: 200)
        ]

        for pointer in pointers {
            let region = VideoRegionGeometry.region(
                from: anchor,
                to: pointer,
                aspectRatio: PhoneVideoPreset.portrait.aspectRatio,
                inside: bounds
            )
            #expect(bounds.contains(region))
            #expect(
                abs(
                    region.width / region.height
                        - PhoneVideoPreset.portrait.aspectRatio
                ) < 0.01
            )
        }
    }

    @Test("Movimentação não deixa a região escapar da tela")
    func movingRegionClampsToBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let original = CGRect(x: 300, y: 200, width: 300, height: 400)

        let topRight = VideoRegionGeometry.moved(
            original,
            by: CGPoint(x: 900, y: 900),
            inside: bounds
        )
        let bottomLeft = VideoRegionGeometry.moved(
            original,
            by: CGPoint(x: -900, y: -900),
            inside: bounds
        )

        #expect(topRight.maxX == bounds.maxX)
        #expect(topRight.maxY == bounds.maxY)
        #expect(bottomLeft.minX == bounds.minX)
        #expect(bottomLeft.minY == bounds.minY)
    }

    @Test("Última região é restaurada em coordenadas normalizadas")
    func storedRegionRoundTrip() throws {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let original = CGRect(x: -1600, y: 140, width: 600, height: 800)
        let selection = CaptureSelection(
            displayID: 42,
            screenFrame: screen,
            region: original
        )

        let stored = StoredCaptureRegion(selection: selection)
        let encoded = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(
            StoredCaptureRegion.self,
            from: encoded
        )
        let restored = try #require(decoded.region(in: screen))

        #expect(decoded.displayID == 42)
        #expect(abs(restored.minX - original.minX) < 0.001)
        #expect(abs(restored.minY - original.minY) < 0.001)
        #expect(abs(restored.width - original.width) < 0.001)
        #expect(abs(restored.height - original.height) < 0.001)
    }

    @Test("Modos de áudio ativam somente as fontes correspondentes")
    func audioModesMapToCaptureSources() {
        #expect(!RecordingAudioMode.none.capturesSystemAudio)
        #expect(!RecordingAudioMode.none.capturesMicrophone)
        #expect(!RecordingAudioMode.microphone.capturesSystemAudio)
        #expect(RecordingAudioMode.microphone.capturesMicrophone)
        #expect(RecordingAudioMode.system.capturesSystemAudio)
        #expect(!RecordingAudioMode.system.capturesMicrophone)
        #expect(RecordingAudioMode.systemAndMicrophone.capturesSystemAudio)
        #expect(RecordingAudioMode.systemAndMicrophone.capturesMicrophone)
    }

    @Test("Nome de vídeo segue o padrão e evita sobrescrita")
    func recordingFileNameUsesReportPattern() throws {
        try withTemporaryDirectory { directory in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
            let date = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 25,
                hour: 11,
                minute: 24
            )))

            let first = ScreenCaptureRecorder.availableDestination(
                in: directory,
                date: date
            )
            #expect(first.lastPathComponent == "20260725_1124_video-laudo.mp4")

            try Data().write(to: first)
            let second = ScreenCaptureRecorder.availableDestination(
                in: directory,
                date: date
            )
            #expect(second.lastPathComponent == "20260725_1124_video-laudo-2.mp4")
        }
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SkjaldrVideoTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
}
