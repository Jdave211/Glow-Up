import Foundation
import AuthenticationServices

/// Manages user session persistence
class SessionManager {
    static let shared = SessionManager()
    // Temporary release gate for App Review: disables routine share/import flows.
    static let isRoutineSharingEnabled = false
    
    private let userIdKey = "com.glowup.userId"
    private let userEmailKey = "com.glowup.userEmail"
    private let userNameKey = "com.glowup.userName"
    private let skinProfileIdKey = "com.glowup.skinProfileId"
    private let isOnboardedKey = "com.glowup.isOnboarded"
    private let isPremiumKey = "com.glowup.isPremium"
    private let hasAIDataConsentKey = "com.glowup.hasAIDataConsent"
    private let hasFaceAnalysisConsentKey = "com.glowup.hasFaceAnalysisConsent"
    private let shippingAddressKey = "com.glowup.shippingAddress"
    private let pendingSharedRoutineTokenKey = "com.glowup.pendingSharedRoutineToken"
    private let routineLibraryKeyPrefix = "com.glowup.routineLibrary."
    
    private init() {}
    
    // MARK: - User
    
    var userId: String? {
        get { UserDefaults.standard.string(forKey: userIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: userIdKey) }
    }
    
    var userEmail: String? {
        get { UserDefaults.standard.string(forKey: userEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: userEmailKey) }
    }
    
    var userName: String? {
        get { UserDefaults.standard.string(forKey: userNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }

    var skinProfileId: String? {
        get { UserDefaults.standard.string(forKey: skinProfileIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: skinProfileIdKey) }
    }
    
    var isOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: isOnboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: isOnboardedKey) }
    }
    
    /// Cached subscription status (source of truth is StoreKit entitlement state)
    var isPremium: Bool {
        get { UserDefaults.standard.bool(forKey: isPremiumKey) }
        set { UserDefaults.standard.set(newValue, forKey: isPremiumKey) }
    }

    var hasAIDataConsent: Bool {
        get { UserDefaults.standard.bool(forKey: hasAIDataConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasAIDataConsentKey) }
    }

    var hasFaceAnalysisConsent: Bool {
        get { UserDefaults.standard.bool(forKey: hasFaceAnalysisConsentKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasFaceAnalysisConsentKey) }
    }
    
    var isSignedIn: Bool { userId != nil }

    func signOut() {
        userId = nil
        userEmail = nil
        userName = nil
        skinProfileId = nil
        isOnboarded = false
        // Do not clear premium here; StoreKit entitlement is Apple ID scoped.
        shippingAddress = nil
    }
    
    // MARK: - Helper Methods
    
    func markOnboarded() {
        isOnboarded = true
    }
    
    func saveUser(_ user: SupabaseUser) {
        if let previousUserId = userId, previousUserId != user.id {
            skinProfileId = nil
        }
        userId = user.id
        userEmail = user.email
        userName = user.name
        isOnboarded = user.onboarded ?? false
    }

    // MARK: - Shipping Address

    struct ShippingAddress: Codable {
        var fullName: String
        var line1: String
        var line2: String
        var city: String
        var state: String
        var zip: String
        var country: String
    }

    var shippingAddress: ShippingAddress? {
        get {
            guard let data = UserDefaults.standard.data(forKey: shippingAddressKey) else { return nil }
            return try? JSONDecoder().decode(ShippingAddress.self, from: data)
        }
        set {
            if let newValue = newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: shippingAddressKey)
            } else {
                UserDefaults.standard.removeObject(forKey: shippingAddressKey)
            }
        }
    }
    
    var hasShippingAddress: Bool {
        shippingAddress != nil
    }

    // MARK: - Routine Library

    struct RoutineLibraryItem: Codable, Identifiable {
        let id: String
        let title: String
        let sourceLabel: String?
        let sourceToken: String?
        let importedAt: Date
        let morning: [FeedRoutineStep]
        let evening: [FeedRoutineStep]
        let weekly: [FeedRoutineStep]
    }

    private var routineLibraryKey: String {
        "\(routineLibraryKeyPrefix)\(userId ?? "guest")"
    }

    var routineLibrary: [RoutineLibraryItem] {
        get {
            guard let data = UserDefaults.standard.data(forKey: routineLibraryKey) else { return [] }
            return (try? JSONDecoder().decode([RoutineLibraryItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: routineLibraryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: routineLibraryKey)
            }
        }
    }

    @discardableResult
    func addRoutineToLibrary(
        title: String,
        morning: [FeedRoutineStep],
        evening: [FeedRoutineStep],
        weekly: [FeedRoutineStep] = [],
        sourceLabel: String? = nil,
        sourceToken: String? = nil
    ) -> RoutineLibraryItem {
        let cleanedMorning = morning.sorted { $0.step < $1.step }
        let cleanedEvening = evening.sorted { $0.step < $1.step }
        let cleanedWeekly = weekly.sorted { $0.step < $1.step }

        let item = RoutineLibraryItem(
            id: UUID().uuidString,
            title: title,
            sourceLabel: sourceLabel,
            sourceToken: sourceToken,
            importedAt: Date(),
            morning: cleanedMorning,
            evening: cleanedEvening,
            weekly: cleanedWeekly
        )

        var all = routineLibrary
        all.insert(item, at: 0)
        // Keep library bounded for lightweight local storage.
        routineLibrary = Array(all.prefix(50))
        return item
    }

    func removeRoutineLibraryItem(id: String) {
        routineLibrary.removeAll { $0.id == id }
    }

    // MARK: - Shared Routine Deep Link Queue

    func queueSharedRoutineToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: pendingSharedRoutineTokenKey)
    }

    func consumePendingSharedRoutineToken() -> String? {
        let token = UserDefaults.standard.string(forKey: pendingSharedRoutineTokenKey)
        UserDefaults.standard.removeObject(forKey: pendingSharedRoutineTokenKey)
        return token
    }
}

extension Notification.Name {
    static let glowUpOpenRoutineImport = Notification.Name("GlowUpOpenRoutineImport")
    static let glowUpRoutineDidUpdate = Notification.Name("GlowUpRoutineDidUpdate")
    static let glowUpNotificationDestination = Notification.Name("GlowUpNotificationDestination")
}
