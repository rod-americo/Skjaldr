import AVFoundation
import CoreGraphics
import Foundation

enum PhoneVideoPreset: String, Codable, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: "Phone Portrait"
        case .landscape: "Phone Landscape"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "iphone.gen3"
        case .landscape: "iphone.gen3.landscape"
        }
    }

    /// Width divided by height. Both ratios reduce to exact integer pairs.
    var aspectRatio: CGFloat {
        switch self {
        case .portrait: 6.0 / 13.0
        case .landscape: 13.0 / 6.0
        }
    }

    var outputSize: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 2340)
        case .landscape: CGSize(width: 2340, height: 1080)
        }
    }
}

enum RecordingAudioMode: String, Codable, CaseIterable, Identifiable {
    case none
    case microphone
    case system
    case systemAndMicrophone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Sem áudio"
        case .microphone: "Microfone"
        case .system: "Áudio do sistema"
        case .systemAndMicrophone: "Sistema + microfone"
        }
    }

    var capturesSystemAudio: Bool {
        self == .system || self == .systemAndMicrophone
    }

    var capturesMicrophone: Bool {
        self == .microphone || self == .systemAndMicrophone
    }
}

enum VideoRecordingPhase: String, Equatable {
    case idle
    case selecting
    case preparing
    case recording
    case finishing

    var isBusy: Bool { self != .idle }
}

enum VideoPrivacySettingsTarget: Equatable {
    case screenCapture
    case microphone

    var buttonTitle: String {
        switch self {
        case .screenCapture: "Abrir Ajustes da Gravação de Tela"
        case .microphone: "Abrir Ajustes do Microfone"
        }
    }

    var settingsURL: URL? {
        let pane: String
        switch self {
        case .screenCapture:
            pane = "Privacy_ScreenCapture"
        case .microphone:
            pane = "Privacy_Microphone"
        }
        return URL(
            string: "x-apple.systempreferences:"
                + "com.apple.preference.security?\(pane)"
        )
    }
}

struct MicrophoneSource: Identifiable, Hashable {
    let id: String
    let name: String

    static func available() -> [MicrophoneSource] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { MicrophoneSource(id: $0.uniqueID, name: $0.localizedName) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct CaptureSelection: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let region: CGRect

    var sourceRect: CGRect {
        CGRect(
            x: region.minX - screenFrame.minX,
            y: screenFrame.maxY - region.maxY,
            width: region.width,
            height: region.height
        )
    }
}

struct StoredCaptureRegion: Codable, Equatable {
    let displayID: UInt32
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(selection: CaptureSelection) {
        let bounds = selection.screenFrame
        displayID = selection.displayID
        x = (selection.region.minX - bounds.minX) / bounds.width
        y = (selection.region.minY - bounds.minY) / bounds.height
        width = selection.region.width / bounds.width
        height = selection.region.height / bounds.height
    }

    func region(in screenFrame: CGRect) -> CGRect? {
        guard screenFrame.width > 0,
              screenFrame.height > 0,
              width > 0,
              height > 0
        else {
            return nil
        }
        let region = CGRect(
            x: screenFrame.minX + x * screenFrame.width,
            y: screenFrame.minY + y * screenFrame.height,
            width: width * screenFrame.width,
            height: height * screenFrame.height
        )
        guard screenFrame.contains(region) else { return nil }
        return region
    }
}

enum VideoRegionGeometry {
    static let minimumLength: CGFloat = 96

    static func region(
        from anchor: CGPoint,
        to pointer: CGPoint,
        aspectRatio: CGFloat,
        inside bounds: CGRect
    ) -> CGRect {
        guard aspectRatio > 0 else { return .zero }

        let signX: CGFloat = pointer.x >= anchor.x ? 1 : -1
        let signY: CGFloat = pointer.y >= anchor.y ? 1 : -1
        var width = abs(pointer.x - anchor.x)
        var height = abs(pointer.y - anchor.y)

        if width / max(height, 1) > aspectRatio {
            height = width / aspectRatio
        } else {
            width = height * aspectRatio
        }

        let availableWidth = signX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let availableHeight = signY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let scale = min(
            1,
            availableWidth / max(width, 1),
            availableHeight / max(height, 1)
        )
        width *= scale
        height *= scale

        return CGRect(
            x: signX > 0 ? anchor.x : anchor.x - width,
            y: signY > 0 ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }

    static func moved(_ region: CGRect, by delta: CGPoint, inside bounds: CGRect) -> CGRect {
        let x = min(max(region.minX + delta.x, bounds.minX), bounds.maxX - region.width)
        let y = min(max(region.minY + delta.y, bounds.minY), bounds.maxY - region.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: region.size)
    }

    static func isValid(_ region: CGRect, aspectRatio: CGFloat) -> Bool {
        region.width >= minimumLength &&
        region.height >= minimumLength &&
        abs(region.width / region.height - aspectRatio) < 0.01
    }
}

enum VideoRecordingError: LocalizedError {
    case screenPermissionDenied
    case microphonePermissionDenied
    case displayUnavailable
    case invalidRegion
    case noMicrophone
    case outputFolderUnavailable
    case recordingDidNotStart
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenPermissionDenied:
            """
            Permita a gravação de tela em Ajustes do Sistema > Privacidade e \
            Segurança. Depois de autorizar, encerre e reabra o Skjaldr.
            """
        case .microphonePermissionDenied:
            "Permita o uso do microfone em Ajustes do Sistema > Privacidade e Segurança."
        case .displayUnavailable:
            "A tela selecionada não está mais disponível."
        case .invalidRegion:
            "Selecione uma região maior antes de iniciar a gravação."
        case .noMicrophone:
            "Nenhum microfone compatível está disponível."
        case .outputFolderUnavailable:
            "A pasta de saída não está disponível para gravação."
        case .recordingDidNotStart:
            "A gravação não pôde ser iniciada."
        case let .recordingFailed(message):
            "A gravação falhou: \(message)"
        }
    }
}

struct VideoCapturePreferences {
    private enum Key {
        static let preset = "video.preset"
        static let audioMode = "video.audioMode"
        static let microphoneID = "video.microphoneID"
        static let outputDirectory = "video.outputDirectory"
        static let portraitRegion = "video.region.portrait"
        static let landscapeRegion = "video.region.landscape"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preset: PhoneVideoPreset {
        get {
            defaults.string(forKey: Key.preset)
                .flatMap(PhoneVideoPreset.init(rawValue:)) ?? .portrait
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.preset) }
    }

    var audioMode: RecordingAudioMode {
        get {
            defaults.string(forKey: Key.audioMode)
                .flatMap(RecordingAudioMode.init(rawValue:)) ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.audioMode) }
    }

    var microphoneID: String? {
        get { defaults.string(forKey: Key.microphoneID) }
        nonmutating set { defaults.set(newValue, forKey: Key.microphoneID) }
    }

    var outputDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.outputDirectory) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Skjaldr", isDirectory: true)
        }
        nonmutating set { defaults.set(newValue.path, forKey: Key.outputDirectory) }
    }

    func storedRegion(for preset: PhoneVideoPreset) -> StoredCaptureRegion? {
        let key = preset == .portrait ? Key.portraitRegion : Key.landscapeRegion
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredCaptureRegion.self, from: data)
    }

    func setStoredRegion(_ region: StoredCaptureRegion, for preset: PhoneVideoPreset) {
        let key = preset == .portrait ? Key.portraitRegion : Key.landscapeRegion
        if let data = try? JSONEncoder().encode(region) {
            defaults.set(data, forKey: key)
        }
    }
}
