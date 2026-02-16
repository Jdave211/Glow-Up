import Foundation

// Supabase Configuration
struct SupabaseConfig {
    static let url = "https://ukhxwxmqjltfjugizbku.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4"
}

// Supabase User model
struct SupabaseUser: Codable {
    let id: String
    let email: String
    let name: String
    let onboarded: Bool?
    let created_at: String?
}

// Supabase Response wrapper
struct SupabaseResponse<T: Codable>: Codable {
    let success: Bool
    let user: T?
    let profile: T?
    let routines: [T]?
    let products: [T]?
    let error: String?
}

class SupabaseService {
    static let shared = SupabaseService()
    private let baseURL: String
    
    private init() {
        // Use local server which connects to Supabase
        baseURL = "http://localhost:4000"
    }
    
    // Create or get user
    func createUser(email: String, name: String) async throws -> SupabaseUser? {
        guard let url = URL(string: "\(baseURL)/api/users") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        
        let body = ["email": email, "name": name]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct UserResponse: Codable {
            let success: Bool
            let user: SupabaseUser?
        }
        
        let response = try JSONDecoder().decode(UserResponse.self, from: data)
        return response.user
    }
    
    // Sign in with Apple
    func signInWithApple(identityToken: String, fullName: PersonNameComponents?) async throws -> SupabaseUser? {
        guard let url = URL(string: "\(baseURL)/api/auth/apple") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        var nameDict: [String: String]? = nil
        if let fullName = fullName {
            nameDict = [
                "givenName": fullName.givenName ?? "",
                "familyName": fullName.familyName ?? ""
            ]
        }
        
        let body: [String: Any] = [
            "identityToken": identityToken,
            "fullName": nameDict ?? [:]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        struct AuthResponse: Codable {
            let success: Bool
            let user: SupabaseUser?
            let error: String?
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data).user
    }
    
    // Check if user is onboarded
    func isUserOnboarded(userId: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/users/\(userId)/onboarded") else {
            throw APIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct OnboardedResponse: Codable {
            let success: Bool
            let onboarded: Bool
        }
        
        let response = try JSONDecoder().decode(OnboardedResponse.self, from: data)
        return response.onboarded
    }
    
    // Get user's latest routine
    func getLatestRoutine(userId: String) async throws -> AnalysisResult? {
        guard let url = URL(string: "\(baseURL)/api/routines/\(userId)") else {
            throw APIError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct RoutinesResponse: Codable {
            let success: Bool
            let routines: [RoutineData]?
        }
        
        struct RoutineData: Codable {
            let id: String
            let routine_data: AnalysisResult?
        }
        
        let response = try JSONDecoder().decode(RoutinesResponse.self, from: data)
        return response.routines?.first?.routine_data
    }
    
    // Save profile to Supabase
    func saveProfile(userId: String, profile: UserProfile) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/profiles") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct ProfileRequest: Codable {
            let userId: String
            let profile: ProfileData
        }
        
        struct ProfileData: Codable {
            let skinType: String
            let skinTone: Double
            let skinGoals: [String]
            let hairType: String
            let concerns: [String]
            let budget: String
            let fragranceFree: Bool
            let washFrequency: String
            let sunscreenUsage: String
            let routineReminders: Bool
            let reminderTime: String
            let photoCheckIns: Bool
        }
        
        let profileData = ProfileData(
            skinType: profile.skinType,
            skinTone: profile.skinTone,
            skinGoals: profile.skinGoals,
            hairType: profile.hairType,
            concerns: profile.concerns,
            budget: profile.budget,
            fragranceFree: profile.fragranceFree,
            washFrequency: profile.washFrequency,
            sunscreenUsage: profile.sunscreenUsage,
            routineReminders: profile.routineReminders,
            reminderTime: profile.reminderTime,
            photoCheckIns: profile.photoCheckIns
        )
        
        let body = ProfileRequest(userId: userId, profile: profileData)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct Response: Codable {
            let success: Bool
        }
        
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.success
    }
    
    // MARK: - Skin Profile (Complete Onboarding Data)
    
    struct SkinProfileResponse: Codable {
        let success: Bool
        let profile: SkinProfileData?
        let error: String?
    }
    
    struct SkinProfileData: Codable {
        let id: String
        let user_id: String
        let skin_type: String?
        let skin_tone: Double?
        let skin_goals: [String]?
        let skin_concerns: [String]?
        let sunscreen_usage: String?
        let fragrance_free: Bool?
        let hair_type: String?
        let hair_concerns: [String]?
        let wash_frequency: String?
        let routine_reminders: Bool?
        let reminder_time: String?
        let photo_check_ins: Bool?
        let onboarding_completed: Bool?
    }
    
    /// Save complete skin profile from onboarding
    func saveSkinProfile(userId: String, profile: UserProfile) async throws -> SkinProfileData? {
        guard let url = URL(string: "\(baseURL)/api/skin-profiles") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Separate skin concerns from hair concerns
        let skinConcernsList = ["acne", "aging", "dark_spots", "texture", "redness", "dryness", "pigmentation", "oiliness", "sensitivity"]
        let hairConcernsList = ["frizz", "breakage", "oily_scalp", "dry_scalp", "thinning", "color_damage", "heat_damage", "scalp_sensitivity"]
        
        let skinConcerns = profile.concerns.filter { skinConcernsList.contains($0) }
        let hairConcerns = profile.concerns.filter { hairConcernsList.contains($0) }

        var parsedPhotos: [String: String] = [:]
        for photoEntry in profile.photos {
            guard let separator = photoEntry.firstIndex(of: ":") else { continue }
            let slot = String(photoEntry[..<separator]).lowercased()
            let valueStart = photoEntry.index(after: separator)
            let payload = String(photoEntry[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { continue }
            if ["front", "left", "right", "scalp"].contains(slot) {
                parsedPhotos[slot] = payload
            }
        }
        
        var body: [String: Any] = [
            "userId": userId,
            "profile": [
                "skinType": profile.skinType,
                "skinTone": profile.skinTone,
                "skinGoals": profile.skinGoals,
                "skinConcerns": skinConcerns,
                "sunscreenUsage": profile.sunscreenUsage,
                "fragranceFree": profile.fragranceFree,
                "hairType": profile.hairType,
                "hairConcerns": hairConcerns,
                "washFrequency": profile.washFrequency,
                "scalpSensitivity": profile.concerns.contains("scalp_sensitivity"),
                "budget": profile.budget,
                "routineReminders": profile.routineReminders,
                "reminderTime": profile.reminderTime,
                "photoCheckIns": profile.photoCheckIns
            ]
        ]

        if !parsedPhotos.isEmpty {
            body["photos"] = parsedPhotos
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorStr = String(data: data, encoding: .utf8) {
                #if DEBUG
                print("Skin Profile Save Error: \(errorStr)")
                #endif
            }
            throw APIError.serverError
        }
        
        let skinProfileResponse = try JSONDecoder().decode(SkinProfileResponse.self, from: data)
        return skinProfileResponse.profile
    }

    /// Load complete skin profile for a user
    func getSkinProfile(userId: String) async throws -> UserProfile? {
        guard let url = URL(string: "\(baseURL)/api/skin-profiles/\(userId)") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        let resp = try JSONDecoder().decode(SkinProfileResponse.self, from: data)
        guard let p = resp.profile else { return nil }
        
        var profile = UserProfile()
        profile.skinType = p.skin_type ?? "normal"
        profile.skinTone = p.skin_tone ?? 0.5
        profile.skinGoals = p.skin_goals ?? []
        profile.concerns = (p.skin_concerns ?? []) + (p.hair_concerns ?? [])
        profile.sunscreenUsage = p.sunscreen_usage ?? "sometimes"
        profile.fragranceFree = p.fragrance_free ?? false
        profile.hairType = p.hair_type ?? "straight"
        profile.washFrequency = p.wash_frequency ?? "2_3_weekly"
        profile.routineReminders = p.routine_reminders ?? true
        profile.reminderTime = p.reminder_time ?? "morning"
        profile.photoCheckIns = p.photo_check_ins ?? true
        
        return profile
    }
    
    // MARK: - Chat Persistence
    
    struct ChatConversation: Codable, Identifiable {
        let id: String
        let user_id: String
        let title: String
        let created_at: String
        let updated_at: String
    }
    
    struct ChatMessageDB: Identifiable {
        let id: String
        let conversation_id: String
        let role: String
        let content: String
        let created_at: String
        let metadata: String?  // raw JSON string for product data
    }
    
    // Custom decoding to handle JSONB metadata field (can be object, null, or absent)
    static func decodeChatMessages(from data: Data) -> [ChatMessageDB] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return [] }
        
        return messages.compactMap { msg -> ChatMessageDB? in
            guard let id = msg["id"] as? String,
                  let convId = msg["conversation_id"] as? String,
                  let role = msg["role"] as? String,
                  let content = msg["content"] as? String,
                  let createdAt = msg["created_at"] as? String else { return nil }
            
            var metadataStr: String? = nil
            if let metaObj = msg["metadata"], !(metaObj is NSNull) {
                if let metaData = try? JSONSerialization.data(withJSONObject: metaObj),
                   let str = String(data: metaData, encoding: .utf8) {
                    metadataStr = str
                }
            }
            
            return ChatMessageDB(id: id, conversation_id: convId, role: role, content: content, created_at: createdAt, metadata: metadataStr)
        }
    }
    
    /// Create a new conversation
    func createConversation(userId: String, title: String = "New Chat") async throws -> ChatConversation? {
        guard let url = URL(string: "\(baseURL)/api/conversations") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userId": userId, "title": title])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct Resp: Codable { let success: Bool; let conversation: ChatConversation? }
        return try JSONDecoder().decode(Resp.self, from: data).conversation
    }
    
    /// List all conversations for a user
    func getConversations(userId: String) async throws -> [ChatConversation] {
        guard let url = URL(string: "\(baseURL)/api/conversations/\(userId)") else { throw APIError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct Resp: Codable { let success: Bool; let conversations: [ChatConversation] }
        return (try? JSONDecoder().decode(Resp.self, from: data).conversations) ?? []
    }
    
    /// Get all messages in a conversation
    func getMessages(conversationId: String) async throws -> [ChatMessageDB] {
        guard let url = URL(string: "\(baseURL)/api/conversations/\(conversationId)/messages") else { throw APIError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        return SupabaseService.decodeChatMessages(from: data)
    }
    
    /// Save a message to a conversation (with optional product metadata)
    func saveMessage(conversationId: String, role: String, content: String, metadata: [String: Any]? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/conversations/\(conversationId)/messages") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["role": role, "content": content]
        if let meta = metadata { body["metadata"] = meta }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let _ = try await URLSession.shared.data(for: request)
    }
    
    /// Update conversation title
    func updateConversationTitle(conversationId: String, title: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/conversations/\(conversationId)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        
        let _ = try await URLSession.shared.data(for: request)
    }
    
    /// Delete a conversation
    func deleteConversation(conversationId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/conversations/\(conversationId)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Insights

    func getLatestInsight(userId: String) async throws -> SkinInsight? {
        guard let url = URL(string: "\(baseURL)/api/insights/\(userId)") else { throw APIError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct Resp: Codable { let success: Bool; let insight: SkinInsight? }
        return (try? JSONDecoder().decode(Resp.self, from: data).insight) ?? nil
    }
    
    // Save routine to Supabase
    func saveRoutine(userId: String, profileId: String, routineData: AnalysisResult) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/routines") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct RoutineRequest: Codable {
            let userId: String
            let profileId: String
            let routineData: AnalysisResult
        }
        
        let body = RoutineRequest(userId: userId, profileId: profileId, routineData: routineData)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct Response: Codable {
            let success: Bool
        }
        
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.success
    }
}
