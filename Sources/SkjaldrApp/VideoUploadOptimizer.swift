import AVFoundation
import CoreVideo
import Foundation

enum VideoUploadOptimizer {
    static let targetVideoBitRate = 6_000_000

    static func optimize(
        sourceURL: URL,
        destinationURL: URL
    ) async throws -> URL {
        let task = Task.detached(priority: .utility) {
            try await transcode(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func transcode(
        sourceURL: URL,
        destinationURL: URL
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.removeItem(at: destinationURL)

        let asset = AVURLAsset(url: sourceURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video)
            .first
        guard let videoTrack else {
            throw VideoUploadError.invalidVideo
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let width = Int(abs(naturalSize.width))
        let height = Int(abs(naturalSize.height))
        guard width > 0, height > 0 else {
            throw VideoUploadError.invalidVideo
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(
            outputURL: destinationURL,
            fileType: .mp4
        )
        writer.shouldOptimizeForNetworkUse = true

        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoUploadError.videoOptimizationFailed
        }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: targetVideoBitRate,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoProfileLevelKey:
                        AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: true
                ]
            ]
        )
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw VideoUploadError.videoOptimizationFailed
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio)
            .first
        {
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: nil
            )
            output.alwaysCopiesSampleData = false
            let formatDescriptions = try await audioTrack.load(
                .formatDescriptions
            )
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: formatDescriptions.first
            )
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            try? fileManager.removeItem(at: destinationURL)
            throw reader.error ?? writer.error
                ?? VideoUploadError.videoOptimizationFailed
        }
        writer.startSession(atSourceTime: .zero)

        do {
            try feed(
                reader: reader,
                videoOutput: videoOutput,
                videoInput: videoInput,
                audioOutput: audioOutput,
                audioInput: audioInput
            )
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? VideoUploadError.videoOptimizationFailed
            }
            return destinationURL
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func feed(
        reader: AVAssetReader,
        videoOutput: AVAssetReaderTrackOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderTrackOutput?,
        audioInput: AVAssetWriterInput?
    ) throws {
        var videoFinished = false
        var audioFinished = audioOutput == nil || audioInput == nil

        while !videoFinished || !audioFinished {
            try Task.checkCancellation()
            var madeProgress = false

            if !videoFinished, videoInput.isReadyForMoreMediaData {
                madeProgress = true
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else {
                        throw VideoUploadError.videoOptimizationFailed
                    }
                } else {
                    videoInput.markAsFinished()
                    videoFinished = true
                }
            }

            if !audioFinished,
               let audioOutput,
               let audioInput,
               audioInput.isReadyForMoreMediaData
            {
                madeProgress = true
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        throw VideoUploadError.videoOptimizationFailed
                    }
                } else {
                    audioInput.markAsFinished()
                    audioFinished = true
                }
            }

            if reader.status == .failed {
                throw reader.error ?? VideoUploadError.videoOptimizationFailed
            }
            if !madeProgress {
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }
}
