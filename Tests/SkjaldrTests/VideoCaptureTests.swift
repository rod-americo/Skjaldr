import AVFoundation
import CoreGraphics
import CoreVideo
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

    @Test("Moldura de gravação acompanha exatamente a região selecionada")
    func recordingOverlayFramesSelectionWithoutCoveringItsBounds() {
        let region = CGRect(x: -1_200, y: 140, width: 480, height: 1_040)
        let borderWidth: CGFloat = 3
        let frame = RecordingRegionOverlayController.windowFrame(
            for: region,
            borderWidth: borderWidth
        )

        #expect(frame.minX == region.minX - borderWidth)
        #expect(frame.minY == region.minY - borderWidth)
        #expect(frame.maxX == region.maxX + borderWidth)
        #expect(frame.maxY == region.maxY + borderWidth)
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

    @Test("Erros de privacidade abrem o painel correto")
    func privacyErrorsUseSpecificSettingsPane() {
        #expect(
            VideoPrivacySettingsTarget.screenCapture.settingsURL?
                .absoluteString.contains("Privacy_ScreenCapture") == true
        )
        #expect(
            VideoPrivacySettingsTarget.microphone.settingsURL?
                .absoluteString.contains("Privacy_Microphone") == true
        )
        #expect(
            VideoPrivacySettingsTarget.screenCapture.buttonTitle
                != VideoPrivacySettingsTarget.microphone.buttonTitle
        )
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

    @Test("Recuperação promove somente MP4 temporário reproduzível")
    func temporaryRecordingRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SkjaldrRecoveryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = directory.appendingPathComponent(
            ".skjaldr-valid.mp4"
        )
        let invalid = directory.appendingPathComponent(
            ".skjaldr-invalid.mp4"
        )
        try await makeSyntheticVideo(at: valid)
        try Data("incompleto".utf8).write(to: invalid)

        let recovered = await ScreenCaptureRecorder
            .recoverTemporaryRecordings(in: directory)

        #expect(recovered.count == 1)
        #expect(!FileManager.default.fileExists(atPath: valid.path))
        #expect(FileManager.default.fileExists(atPath: invalid.path))
        let output = try #require(recovered.first)
        #expect(output.lastPathComponent.contains("_video-laudo"))
        #expect(await ScreenCaptureRecorder.isPlayableRecording(output))
    }

    @Test("Otimização cria MP4 de upload e preserva o original")
    func uploadOptimizationPreservesOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SkjaldrOptimizationTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.mp4")
        let optimized = directory.appendingPathComponent("optimized.mp4")
        try await makeSyntheticVideo(at: original)

        let result = try await VideoUploadOptimizer.optimize(
            sourceURL: original,
            destinationURL: optimized
        )

        #expect(result == optimized)
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(await ScreenCaptureRecorder.isPlayableRecording(optimized))
        #expect(VideoUploadOptimizer.targetVideoBitRate == 6_000_000)
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

    private func makeSyntheticVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        #expect(writer.canAdd(input))
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            nil,
            try #require(adaptor.pixelBufferPool),
            &pixelBuffer
        )
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(pixelBuffer)
        #expect(adaptor.append(buffer, withPresentationTime: .zero))
        #expect(
            adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: 1, timescale: 30)
            )
        )
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }
}
