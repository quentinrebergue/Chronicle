import Foundation
import UserNotifications

/// Notifications locales invitant à générer les récits (hebdo / mensuel / annuel).
/// Tout est local — aucune notification push distante.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Posté quand l'utilisateur tape une notification → MainTabView bascule sur la Bibliothèque
    static let openLibraryNotification = Notification.Name("otobio.openLibrary")

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Au lancement : active le delegate et replanifie si la permission est déjà accordée.
    /// Ne déclenche jamais le popup de permission.
    func rescheduleIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            scheduleAll()
        }
    }

    /// À appeler à un moment opportun (après la première entrée enregistrée),
    /// pas au premier lancement.
    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            if settings.authorizationStatus == .authorized {
                scheduleAll()
            }
            return
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            AppLogger.log("🔔 Permission notifications: \(granted ? "accordée" : "refusée")")
            if granted { scheduleAll() }
        } catch {
            AppLogger.log("⚠️ Permission notifications: \(error)")
        }
    }

    // MARK: - Planification

    func scheduleAll() {
        scheduleWeekly()
        scheduleMonthly()
        scheduleYearly()
        AppLogger.log("🔔 Rappels de récits planifiés (hebdo / mensuel / annuel)")
    }

    /// Dimanche 19h — récit de la semaine
    private func scheduleWeekly() {
        var components = DateComponents()
        components.weekday = 1 // dimanche
        components.hour = 19
        schedule(
            id: "otobio.weekly",
            title: "Ton récit de la semaine t'attend",
            body: "Otobio est prêt à écrire le chapitre de ta semaine. Ouvre la bibliothèque pour le générer.",
            dateMatching: components
        )
    }

    /// Le 1er du mois à 10h — chapitre du mois écoulé
    private func scheduleMonthly() {
        var components = DateComponents()
        components.day = 1
        components.hour = 10
        schedule(
            id: "otobio.monthly",
            title: "Un nouveau chapitre à écrire",
            body: "Le mois est terminé. Génère ton chapitre mensuel dans la bibliothèque.",
            dateMatching: components
        )
    }

    /// Le 1er janvier à 11h — chapitre de l'année écoulée
    private func scheduleYearly() {
        var components = DateComponents()
        components.month = 1
        components.day = 1
        components.hour = 11
        schedule(
            id: "otobio.yearly",
            title: "Une année de ta vie, racontée",
            body: "L'année s'est achevée. Otobio peut maintenant écrire son chapitre.",
            dateMatching: components
        )
    }

    private func schedule(id: String, title: String, body: String, dateMatching components: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: Self.openLibraryNotification, object: nil)
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Afficher la notification même si l'app est ouverte
        completionHandler([.banner, .sound])
    }
}
