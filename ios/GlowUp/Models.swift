import Foundation

// MARK: - Price Formatting Extension
extension Double {
    /// App-only markup per product unit (not persisted to DB prices).
    static let appUnitMarkup: Double = 1.0
    
    /// Rounds up the price to the nearest whole number
    var roundedUpPrice: Int {
        return Int(ceil(self))
    }
    
    /// Adds the app markup for one unit.
    var withAppMarkup: Double {
        self + Double.appUnitMarkup
    }
    
    /// Price + app markup, then rounded up for display labels.
    var roundedUpPriceWithMarkup: Int {
        Int(ceil(withAppMarkup))
    }
}

// MARK: - User Profile
struct UserProfile: Codable {
    var name: String = ""
    var skinType: String = "normal"
    var hairType: String = "straight"
    var concerns: [String] = []
    var budget: String = "medium"
    var fragranceFree: Bool = false
    
    // Skin fields
    var skinTone: Double = 0.5 // 0.0 (Fair) to 1.0 (Deep)
    var sunscreenUsage: String = "sometimes"
    var skinGoals: [String] = [] // glass_skin, clear_skin, brightening, etc.
    
    // Hair fields
    var washFrequency: String = "2_3_weekly" // More inclusive options
    
    // Reminders
    var routineReminders: Bool = true
    var reminderTime: String = "morning" // morning, evening, both
    var photoCheckIns: Bool = true // Biweekly photo uploads
    
    // Photos (base64 or URLs)
    var photos: [String] = []
}

// MARK: - UserProfile Normalization
extension UserProfile {
    func normalized() -> UserProfile {
        var p = self
        p.skinType = p.skinType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        p.hairType = p.hairType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        p.budget = p.budget.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        p.sunscreenUsage = p.sunscreenUsage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        p.reminderTime = p.reminderTime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        p.washFrequency = p.washFrequency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func normalizeTag(_ input: String) -> String {
            let cleaned = input
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: "__", with: "_")
            return cleaned
        }

        let concernMap: [String: String] = [
            "dark_spots": "dark_spots",
            "darkspots": "dark_spots",
            "pigmentation": "pigmentation",
            "brightening": "brightening",
            "uneven_tone": "pigmentation",
            "texture": "texture",
            "pores": "texture",
            "acne": "acne",
            "breakouts": "acne",
            "aging": "aging",
            "anti_aging": "aging",
            "wrinkles": "aging",
            "redness": "redness",
            "sensitivity": "sensitivity",
            "dryness": "dryness",
            "oiliness": "oiliness",
            "frizz": "frizz",
            "breakage": "breakage",
            "oily_scalp": "oily_scalp",
            "dry_scalp": "dry_scalp",
            "thinning": "thinning",
            "color_damage": "color_damage",
            "heat_damage": "heat_damage",
            "scalp_sensitivity": "scalp_sensitivity"
        ]

        let goalMap: [String: String] = [
            "glass_skin": "glass_skin",
            "clear_skin": "clear_skin",
            "brightening": "brightening",
            "anti_aging": "anti_aging",
            "barrier_repair": "barrier_repair",
            "hydration": "hydration",
            "even_tone": "brightening"
        ]

        p.concerns = Array(Set(p.concerns.map { concernMap[normalizeTag($0)] ?? normalizeTag($0) })).sorted()
        p.skinGoals = Array(Set(p.skinGoals.map { goalMap[normalizeTag($0)] ?? normalizeTag($0) })).sorted()

        if p.skinType.isEmpty { p.skinType = "normal" }
        if p.hairType.isEmpty { p.hairType = "straight" }
        if p.budget.isEmpty { p.budget = "medium" }
        if p.sunscreenUsage.isEmpty { p.sunscreenUsage = "sometimes" }
        if p.washFrequency.isEmpty { p.washFrequency = "2_3_weekly" }
        if p.reminderTime.isEmpty { p.reminderTime = "morning" }

        return p
    }
}

// MARK: - Analysis Result
struct AnalysisResult: Codable {
    let agents: [AgentResult]
    let summary: Summary
    let inference: InferenceData?
}

// MARK: - Inference Data from RAG
struct InferenceData: Codable {
    let products: [InferenceProduct]?
    let routine: RoutineSummary?
    let summary: String?
    let personalized_tips: [String]?
}

struct AgentResult: Codable, Identifiable {
    var id: String { agentName }
    let agentName: String
    let emoji: String
    let thinking: [ThinkingStep]
    let recommendations: AnyCodable
    let confidence: Double
}

struct ThinkingStep: Codable, Identifiable {
    var id: String { thought }
    let thought: String
    let conclusion: String?
}

struct Summary: Codable {
    let totalProducts: Int
    let totalCost: Double
    let overallConfidence: String
    let routine: RoutineSummary?
    let personalized_tips: [String]?
}

// MARK: - Routine from LLM inference
struct RoutineSummary: Codable {
    let morning: [RoutineStep]?
    let evening: [RoutineStep]?
    let weekly: [RoutineStep]?
}

struct RoutineStep: Codable, Identifiable {
    var id: String { "\(step)-\(name)" }
    let step: Int
    let name: String
    let product: InferenceProduct?
    let instructions: String
    let frequency: String
}

struct InferenceProduct: Codable, Identifiable {
    let id: String
    let name: String
    let brand: String
    let price: Double
    let category: String
    let description: String?
    let image_url: String?
    let rating: Double?
    let similarity: Double?
    let buy_link: String?
}

// MARK: - Product
struct Product: Codable, Identifiable {
    let id: Int
    let name: String
    let price: Double
    let category: String
    let rating: Double
    let match: Double
}

// MARK: - AnyCodable wrapper for dynamic JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([ProductWrapper].self) {
            value = array
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

struct ProductWrapper: Codable, Identifiable {
    let id: Int
    let name: String
    let price: Double
    let category: String
    let rating: Double
    let match: Double
}

// MARK: - Home Feed Response
struct HomeFeedResponse: Codable {
    let success: Bool
    let user_summary: String
    let sections: HomeFeedSections
    let routine: FeedRoutine?
    let routine_has_products: Bool?
    let tips: [String]
    let confidence: Double?
    let generated_at: String?
}

struct SkinInsight: Codable, Identifiable {
  let id: String
  let user_id: String
  let skin_score: Double?
  let hydration: String?
  let protection: String?
  let texture: String?
  let notes: String?
  let source: String?
  let created_at: String?
}

struct HomeFeedSections: Codable {
    let picked_for_you: [FeedProduct]
    let trending: [FeedProduct]
    let new_arrivals: [FeedProduct]
}

struct FeedProduct: Codable, Identifiable {
    let id: String
    let name: String
    let brand: String
    let price: Double
    let category: String
    let description: String?
    let image_url: String?
    let rating: Double?
    let review_count: Int?
    let similarity: Double?
    let buy_link: String?
    let target_skin_type: [String]?
    let target_concerns: [String]?
    let attributes: [String]?
    
    /// Convert to InferenceProduct for compatibility with existing views
    var asInferenceProduct: InferenceProduct {
        InferenceProduct(
            id: id, name: name, brand: brand, price: price,
            category: category, description: description,
            image_url: image_url, rating: rating, similarity: similarity,
            buy_link: buy_link
        )
    }
}

struct FeedRoutine: Codable {
    let morning: [FeedRoutineStep]?
    let evening: [FeedRoutineStep]?
    let weekly: [FeedRoutineStep]?
}

struct FeedRoutineStep: Codable, Identifiable {
    var id: String { "\(step)-\(name)" }
    let step: Int
    let name: String
    let tip: String?
    
    // Product-enriched fields (from saved routine)
    let product_id: String?
    let product_name: String?
    let product_brand: String?
    let product_price: Double?
    let product_image: String?
    let buy_link: String?
    
    /// Whether this step has a real product attached
    var hasProduct: Bool { product_id != nil && !(product_id?.isEmpty ?? true) }
}

// MARK: - Agent Info
struct AgentInfo {
    let emoji: String
    let name: String
    let color: String
    
    static let agents: [AgentInfo] = [
        AgentInfo(emoji: "🧴", name: "Skin", color: "FF6B9D"),
        AgentInfo(emoji: "💇", name: "Hair", color: "FF8FB1"),
        AgentInfo(emoji: "🔍", name: "Match", color: "FFB4C8"),
        AgentInfo(emoji: "💰", name: "Budget", color: "FFC8DD")
    ]
}

// MARK: - Skin Page Response (Agent-powered)
struct SkinPageResponse: Codable {
    let success: Bool
    let profile: SkinPageProfile
    let routine: SkinPageRoutine
    let insights: SkinPageInsights
    let streaks: SkinPageStreaks
    let today_checkins: [String]
    let agent: SkinPageAgent
}

struct SkinPageProfile: Codable {
    let skin_type: String
    let skin_tone: String
    let skin_tone_value: Double
    let skin_goals: [String]
    let skin_concerns: [String]
    let sunscreen_usage: String
    let fragrance_free: Bool
    let hair_type: String?
    let hair_concerns: [String]?
    let wash_frequency: String?
    let budget: String
}

struct SkinPageRoutine: Codable {
    let morning: [SkinPageRoutineStep]
    let evening: [SkinPageRoutineStep]
}

struct SkinPageRoutineStep: Codable, Identifiable {
    var id: String { "\(step)-\(name)" }
    let step: Int
    let name: String
    let product_name: String?
    let product_brand: String?
    let product_price: Double?
    let product_image: String?
    let product_id: String?
    let instructions: String?
    let frequency: String?
}

struct SkinPageInsights: Codable {
    let skin_score: Double?
    let hydration: String?
    let protection: String?
    let texture: String?
}

struct SkinPageStreaks: Codable {
    let morning: Int
    let evening: Int
}

struct SkinPageAgent: Codable {
    let page_title: String
    let page_subtitle: String
    let skin_assessment: String
    let weekly_focus: String
    let tips: [String]
    let progress_note: String
}

// MARK: - Skin Tone Labels
struct SkinToneInfo {
    static func label(for value: Double) -> String {
        switch value {
        case 0..<0.15: return "Fair"
        case 0.15..<0.3: return "Light"
        case 0.3..<0.45: return "Light-Medium"
        case 0.45..<0.6: return "Medium"
        case 0.6..<0.75: return "Medium-Deep"
        case 0.75..<0.9: return "Deep"
        default: return "Rich Deep"
        }
    }
    
    static func color(for value: Double) -> String {
        // Fitzpatrick scale inspired colors
        switch value {
        case 0..<0.15: return "FFE4D6"
        case 0.15..<0.3: return "F5D0C5"
        case 0.3..<0.45: return "D4A574"
        case 0.45..<0.6: return "C68642"
        case 0.6..<0.75: return "8D5524"
        case 0.75..<0.9: return "5C3A21"
        default: return "3D2314"
        }
    }
}
