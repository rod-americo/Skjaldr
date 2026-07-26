import AppKit
@preconcurrency import UserNotifications

@MainActor
final class VideoCompletionNotificationController:
    NSObject,
    UNUserNotificationCenterDelegate
{
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func presentIfApplicationIsInBackground(url: URL) {
        if NSApp.isActive,
           let keyWindow = NSApp.keyWindow,
           keyWindow.isVisible,
           !(keyWindow is NSPanel)
        {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Vídeo concluído"
        content.body = "O link foi criado e copiado: \(url.absoluteString)"
        content.sound = .default
        content.threadIdentifier = "skjaldr-video-completed"
        content.userInfo = ["publicURL": url.absoluteString]

        center.add(
            UNNotificationRequest(
                identifier: "video-completed-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
