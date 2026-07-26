import AppKit
import OSLog
@preconcurrency import UserNotifications

@MainActor
final class VideoCompletionNotificationController:
    NSObject,
    UNUserNotificationCenterDelegate
{
    private let center = UNUserNotificationCenter.current()
    private let fallback: (URL) -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.skjaldr.app",
        category: "VideoNotification"
    )

    init(fallback: @escaping (URL) -> Void) {
        self.fallback = fallback
        super.init()
        center.delegate = self
    }

    func present(url: URL) {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                self?.deliver(url: url, settings: settings)
            }
        }
    }

    private func deliver(url: URL, settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .notDetermined:
            center.requestAuthorization(
                options: [.alert, .sound]
            ) { [weak self] granted, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.schedule(url: url)
                    } else {
                        self.logger.error(
                            """
                            Notificação não autorizada: \
                            \(error?.localizedDescription ?? "negada", privacy: .public)
                            """
                        )
                        self.fallback(url)
                    }
                }
            }
        case .authorized, .provisional, .ephemeral:
            guard settings.alertSetting == .enabled,
                  settings.alertStyle != .none
            else {
                logger.notice(
                    "Alertas do Skjaldr estão desativados; usando fallback"
                )
                fallback(url)
                return
            }
            schedule(url: url)
        case .denied:
            logger.notice(
                "Notificações do Skjaldr foram negadas; usando fallback"
            )
            fallback(url)
        @unknown default:
            fallback(url)
        }
    }

    private func schedule(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Vídeo concluído"
        content.body = "O link foi criado e copiado: \(url.absoluteString)"
        content.sound = .default
        content.interruptionLevel = .active
        content.threadIdentifier = "skjaldr-video-completed"
        content.userInfo = ["publicURL": url.absoluteString]

        let identifier = "video-completed-\(UUID().uuidString)"
        center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
        ) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.logger.error(
                    """
                    Falha ao publicar notificação: \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
                self?.fallback(url)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let value = response.notification.request.content
            .userInfo["publicURL"] as? String
        if let value, let url = URL(string: value) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
