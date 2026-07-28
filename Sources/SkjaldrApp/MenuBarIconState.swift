import Foundation

enum MenuBarIconState: Equatable {
    case app
    case recording
    case uploading
    case uploadCompleted

    static func resolve(
        recordingPhase: VideoRecordingPhase,
        uploadPhase: VideoUploadPhase,
        isUploadCompletionVisible: Bool
    ) -> Self {
        if recordingPhase == .recording || recordingPhase == .finishing {
            return .recording
        }

        switch uploadPhase {
        case .preparing, .uploading, .confirming:
            return .uploading
        case .completed where isUploadCompletionVisible:
            return .uploadCompleted
        case .idle, .completed, .failed:
            return .app
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .app:
            "Skjaldr"
        case .recording:
            "Skjaldr, recording"
        case .uploading:
            "Skjaldr, uploading"
        case .uploadCompleted:
            "Skjaldr, upload completed and link copied"
        }
    }
}
