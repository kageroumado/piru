import UserNotifications

nonisolated extension UNMutableNotificationContent {
    /// The fields every Piru notification sets, built in one place so the
    /// schedulers (`SessionNotificationScheduler`, `DoseNotificationManager`) cannot
    /// drift on the basics. Policy stays with the caller: quiet-hours gating,
    /// quiet-tier delivery, relevance, and `userInfo` are site-specific.
    ///
    /// With more than one profile on the device the title names whose
    /// journal it is about ("Alice · Concerta"; ``ProfileScope``).
    convenience init(
        title: String,
        body: String,
        category: String,
        threadIdentifier: String? = nil,
        sound: UNNotificationSound? = .default,
        interruptionLevel: UNNotificationInterruptionLevel = .active,
    ) {
        self.init()
        self.title = ProfileScope.personalized(title)
        self.body = body
        categoryIdentifier = category
        if let threadIdentifier {
            self.threadIdentifier = threadIdentifier
        }
        self.sound = sound
        self.interruptionLevel = interruptionLevel
    }
}
