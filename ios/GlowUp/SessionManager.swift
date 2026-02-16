import Foundation
import AuthenticationServices

/// Manages user session persistence
class SessionManager {
    static let shared = SessionManager()
    
    private let userIdKey = "com.glowup.userId"
    private let userEmailKey = "com.glowup.userEmail"
    private let userNameKey = "com.glowup.userName"
    private let isOnboardedKey = "com.glowup.isOnboarded"
    private let isPremiumKey = "com.glowup.isPremium"
    private let shippingAddressKey = "com.glowup.shippingAddress"
    
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
    
    var isOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: isOnboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: isOnboardedKey) }
    }
    
    /// Cached subscription status (source of truth is StoreKit entitlement state)
    var isPremium: Bool {
        get { UserDefaults.standard.bool(forKey: isPremiumKey) }
        set { UserDefaults.standard.set(newValue, forKey: isPremiumKey) }
    }
    
    var isSignedIn: Bool { userId != nil }

    func signOut() {
        userId = nil
        userEmail = nil
        userName = nil
        isOnboarded = false
        // Do not clear premium here; StoreKit entitlement is Apple ID scoped.
        shippingAddress = nil
    }
    
    // MARK: - Helper Methods
    
    func markOnboarded() {
        isOnboarded = true
    }
    
    func saveUser(_ user: SupabaseUser) {
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
}
