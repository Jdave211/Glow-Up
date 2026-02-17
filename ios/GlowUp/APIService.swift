import Foundation

class APIService {
    static let shared = APIService()
    private let baseURL = "https://glowup-15ce3345c8f8.herokuapp.com"
    
    private init() {}
    
    // MARK: - Analyze (onboarding)
    
    func analyze(profile: UserProfile, userId: String? = nil) async throws -> AnalysisResult {
        guard let url = URL(string: "\(baseURL)/api/analyze") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90 // longer timeout — routine gen does multiple DB lookups
        
        // Encode profile + userId together so server can auto-save the routine
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any] ?? [:]
        if let uid = userId { dict["userId"] = uid }
        request.httpBody = try JSONSerialization.data(withJSONObject: dict)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }
    
    // MARK: - Chat
    
    struct ChatResponse {
        let message: String
        let title: String?
        let products: [FeedProduct]
        let productMap: [String: FeedProduct]
    }
    
    func chat(messages: [[String: String]], userId: String?, conversationId: String? = nil) async throws -> ChatResponse {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        var body: [String: Any] = ["messages": messages]
        if let uid = userId { body["userId"] = uid }
        if let convId = conversationId { body["conversationId"] = convId }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            throw APIError.decodingError
        }
        
        let title = json["title"] as? String
        let productsData = json["products"] as? [[String: Any]] ?? []
        let productsJSON = try JSONSerialization.data(withJSONObject: productsData)
        let decodedProducts = (try? JSONDecoder().decode([FeedProduct].self, from: productsJSON)) ?? []
        
        var productMap: [String: FeedProduct] = [:]
        if let mapData = json["product_map"] as? [String: [String: Any]] {
            for (key, value) in mapData {
                if let itemJSON = try? JSONSerialization.data(withJSONObject: value),
                   let product = try? JSONDecoder().decode(FeedProduct.self, from: itemJSON) {
                    productMap[key] = product
                }
            }
        }
        if productMap.isEmpty {
            for p in decodedProducts { productMap[p.id] = p }
        }
        
        return ChatResponse(message: message, title: title, products: decodedProducts, productMap: productMap)
    }

    func guestChat(messages: [[String: String]]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat/guest") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": messages])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            throw APIError.decodingError
        }

        return message
    }
    
    // MARK: - Skin Page
    
    func fetchSkinPage(userId: String, forceRefresh: Bool = false) async throws -> SkinPageResponse {
        let refreshParam = forceRefresh ? "?refresh=true" : ""
        guard let url = URL(string: "\(baseURL)/api/skin-page/\(userId)\(refreshParam)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        return try JSONDecoder().decode(SkinPageResponse.self, from: data)
    }
    
    // MARK: - Home Feed
    
    func fetchHomeFeed(userId: String) async throws -> HomeFeedResponse {
        guard let url = URL(string: "\(baseURL)/api/home-feed/\(userId)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        return try JSONDecoder().decode(HomeFeedResponse.self, from: data)
    }
    
    // MARK: - Orders
    
    struct OrderTrackingEvent: Codable {
        let status: String
        let message: String
        let at: String
    }
    
    struct OrderTracking: Codable {
        let orderId: String
        let userId: String
        let retailer: String
        let status: String
        let trackingUrl: String
        let estimatedDelivery: String?
        let events: [OrderTrackingEvent]
        let updatedAt: String
    }
    
    struct OrderCreateResponse: Codable {
        let success: Bool
        let orderId: String?
        let tracking: TrackingSummary?
        
        struct TrackingSummary: Codable {
            let status: String
            let trackingUrl: String
            let estimatedDelivery: String?
        }
    }
    
    struct LatestTrackingResponse: Codable {
        let success: Bool
        let tracking: OrderTracking
    }
    
    func createOrder(userId: String, items: [CartItem], shippingAddress: [String: Any]? = nil) async throws -> OrderCreateResponse {
        guard let url = URL(string: "\(baseURL)/api/orders") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let orderItems: [[String: Any]] = items.map {
            [
                "productId": $0.product.id,
                "name": $0.product.name,
                "brand": $0.product.brand,
                "url": $0.product.buy_link ?? "",
                "quantity": $0.quantity,
                "price": $0.product.price
            ]
        }
        
        let address = shippingAddress ?? (SessionManager.shared.shippingAddress.map { addr in
            [
                "fullName": addr.fullName,
                "line1": addr.line1,
                "line2": addr.line2,
                "city": addr.city,
                "state": addr.state,
                "zip": addr.zip,
                "country": addr.country
            ]
        } ?? ["formatted": "Not set"])
        
        let body: [String: Any] = [
            "userId": userId,
            "items": orderItems,
            "shippingAddress": address
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        return try JSONDecoder().decode(OrderCreateResponse.self, from: data)
    }
    
    func getLatestOrderTracking(userId: String) async throws -> OrderTracking {
        guard let url = URL(string: "\(baseURL)/api/orders/user/\(userId)/latest-tracking") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        return try JSONDecoder().decode(LatestTrackingResponse.self, from: data).tracking
    }

    // MARK: - Cart

    struct CartResponse: Codable {
        let success: Bool
        let items: [CartItemDTO]
    }

    struct CartItemDTO: Codable {
        let product: InferenceProduct
        let quantity: Int
    }

    struct CartAnalysisResponse: Codable {
        let success: Bool
        let items: [CartAnalysisItem]
    }

    struct CartAnalysisItem: Codable {
        let product_id: String
        let label: String
        let reason: String
        let score: Int
    }

    func getCart(userId: String) async throws -> [CartItem] {
        guard let url = URL(string: "\(baseURL)/api/cart/\(userId)") else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        let result = try JSONDecoder().decode(CartResponse.self, from: data)
        return result.items.map { CartItem(product: $0.product, quantity: $0.quantity) }
    }

    func upsertCartItem(userId: String, productId: String, quantity: Int) async throws {
        guard let url = URL(string: "\(baseURL)/api/cart/items") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userId": userId, "productId": productId, "quantity": quantity
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func removeCartItem(userId: String, productId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/cart/items") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userId": userId, "productId": productId
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func clearCart(userId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/cart/\(userId)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func analyzeCart(userId: String, productIds: [String]) async throws -> [CartAnalysisItem] {
        guard let url = URL(string: "\(baseURL)/api/cart/analyze") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userId": userId, "productIds": productIds
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        return try JSONDecoder().decode(CartAnalysisResponse.self, from: data).items
    }
    
    // MARK: - Integrate Product into Routine
    
    func integrateProductIntoRoutine(userId: String, productId: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/routine/integrate-product") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "userId": userId, "productId": productId
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            #if DEBUG
            print("⚠️ integrateProductIntoRoutine failed")
            #endif
            return
        }
    }

    struct RoutineUpdateStep: Codable {
        let step: Int
        let name: String
        let instructions: String
        let frequency: String
        let product_id: String?
        let product_name: String?
    }

    private struct RoutineUpdateRequest: Codable {
        let userId: String
        let routine: RoutinePayload
        let summary: String?

        struct RoutinePayload: Codable {
            let morning: [RoutineUpdateStep]
            let evening: [RoutineUpdateStep]
            let weekly: [RoutineUpdateStep]
        }
    }

    private struct RoutineSearchResponse: Codable {
        let success: Bool
        let products: [FeedProduct]
    }

    struct RoutineShareResponse: Codable {
        let success: Bool
        let share_url: String
        let app_deep_link: String?
        let routine_type: String?
    }

    func searchRoutineProducts(
        userId: String?,
        query: String,
        category: String? = nil,
        limit: Int = 8
    ) async throws -> [FeedProduct] {
        guard let url = URL(string: "\(baseURL)/api/routine/search-products") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        var body: [String: Any] = [
            "query": query,
            "limit": max(1, min(limit, 20))
        ]
        if let userId { body["userId"] = userId }
        if let category, !category.isEmpty { body["category"] = category }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        return try JSONDecoder().decode(RoutineSearchResponse.self, from: data).products
    }

    func updateRoutine(
        userId: String,
        morning: [RoutineUpdateStep],
        evening: [RoutineUpdateStep],
        weekly: [RoutineUpdateStep],
        summary: String? = nil
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/routine/update") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let payload = RoutineUpdateRequest(
            userId: userId,
            routine: .init(morning: morning, evening: evening, weekly: weekly),
            summary: summary
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
    }

    func createRoutineShareLink(userId: String, routineType: String? = nil) async throws -> RoutineShareResponse {
        guard let url = URL(string: "\(baseURL)/api/routine/share") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        var body: [String: Any] = ["userId": userId]
        if let routineType, !routineType.isEmpty {
            body["routineType"] = routineType
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }

        return try JSONDecoder().decode(RoutineShareResponse.self, from: data)
    }
    
    // MARK: - Routine Check-ins
    
    struct RoutineCheckinsResponse: Codable {
        let success: Bool
        let checkins: [String]
        let streaks: StreaksResponse
    }
    
    struct StreaksResponse: Codable {
        let morning: Int
        let evening: Int
    }
    
    func getTodayCheckins(userId: String, date: String? = nil) async throws -> RoutineCheckinsResponse {
        var urlString = "\(baseURL)/api/routine-checkins/\(userId)/today"
        if let date = date { urlString += "?date=\(date)" }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        return try JSONDecoder().decode(RoutineCheckinsResponse.self, from: data)
    }
    
    func markStepComplete(userId: String, routineType: String, stepId: String, stepName: String, date: String? = nil) async throws -> StreaksResponse {
        guard let url = URL(string: "\(baseURL)/api/routine-checkins/complete") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "userId": userId, "routineType": routineType,
            "stepId": stepId, "stepName": stepName
        ]
        if let date = date { body["date"] = date }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streaksDict = json["streaks"] as? [String: Int] else {
            throw APIError.decodingError
        }
        return StreaksResponse(morning: streaksDict["morning"] ?? 0, evening: streaksDict["evening"] ?? 0)
    }
    
    func markStepIncomplete(userId: String, routineType: String, stepId: String, date: String? = nil) async throws -> StreaksResponse {
        guard let url = URL(string: "\(baseURL)/api/routine-checkins/incomplete") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "userId": userId, "routineType": routineType, "stepId": stepId
        ]
        if let date = date { body["date"] = date }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streaksDict = json["streaks"] as? [String: Int] else {
            throw APIError.decodingError
        }
        return StreaksResponse(morning: streaksDict["morning"] ?? 0, evening: streaksDict["evening"] ?? 0)
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError: return "Server error"
        case .decodingError: return "Failed to parse response"
        case .timeout: return "Request timed out"
        }
    }
}
