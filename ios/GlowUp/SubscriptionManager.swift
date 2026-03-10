import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    enum Plan: String, CaseIterable, Identifiable {
        case weekly
        case monthly

        var id: String { rawValue }

        var periodLabel: String {
            switch self {
            case .weekly: return "week"
            case .monthly: return "month"
            }
        }

        var fallbackPrice: String {
            switch self {
            case .weekly: return "$2.99"
            case .monthly: return "$6.99"
            }
        }
    }

    static let shared = SubscriptionManager()

    @Published private(set) var weeklyProduct: StoreKit.Product?
    @Published private(set) var monthlyProduct: StoreKit.Product?
    @Published private(set) var isPremium: Bool = SessionManager.shared.isPremium
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInProgress = false
    @Published var errorMessage: String?

    private let defaultWeeklyProductId = "com.glowup.premium.weekly"
    private let defaultMonthlyProductId = "com.glowup.premium.month"
    private let legacyMonthlyProductIds = [
        "com.glowup.premium.monthly",
        "com.glowup.premium",
        "com.looksmaxx.premium",
        "com.looksmaxx.app.premium"
    ]

    private var updatesTask: Task<Void, Never>?
    private var lastSyncedSubscriptionSignature: String?
    private var subscriptionSyncInFlightSignature: String?

    private var bundleDerivedWeeklyProductId: String? {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else { return nil }
        return "\(bundleId).premium.weekly"
    }

    private var bundleDerivedMonthlyProductId: String? {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else { return nil }
        return "\(bundleId).premium.monthly"
    }

    var weeklyProductId: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "PREMIUM_WEEKLY_PRODUCT_ID") as? String,
           !fromPlist.isEmpty {
            return fromPlist
        }
        if let derived = bundleDerivedWeeklyProductId {
            return derived
        }
        return defaultWeeklyProductId
    }

    var monthlyProductId: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "PREMIUM_MONTHLY_PRODUCT_ID") as? String,
           !fromPlist.isEmpty {
            return fromPlist
        }
        if let derived = bundleDerivedMonthlyProductId {
            return derived
        }
        return defaultMonthlyProductId
    }

    private var candidateProductIds: [String] {
        var ids: [String] = [weeklyProductId, monthlyProductId]

        if let derivedWeekly = bundleDerivedWeeklyProductId, !ids.contains(derivedWeekly) {
            ids.append(derivedWeekly)
        }
        if let derivedMonthly = bundleDerivedMonthlyProductId, !ids.contains(derivedMonthly) {
            ids.append(derivedMonthly)
        }
        if !ids.contains(defaultWeeklyProductId) {
            ids.append(defaultWeeklyProductId)
        }
        if !ids.contains(defaultMonthlyProductId) {
            ids.append(defaultMonthlyProductId)
        }
        for legacyId in legacyMonthlyProductIds where !ids.contains(legacyId) {
            ids.append(legacyId)
        }

        return ids
    }

    private init() {
        updatesTask = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func displayPrice(for plan: Plan) -> String {
        switch plan {
        case .weekly:
            return weeklyProduct?.displayPrice ?? plan.fallbackPrice
        case .monthly:
            return monthlyProduct?.displayPrice ?? plan.fallbackPrice
        }
    }

    func purchase(plan: Plan) async -> Bool {
        errorMessage = nil

        if weeklyProduct == nil || monthlyProduct == nil {
            await loadProducts()
        }

        guard let product = product(for: plan) else {
            errorMessage = "Subscriptions are temporarily unavailable. Please try again soon."
            return false
        }

        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                await transaction.finish()
                await refreshEntitlements()
                return isPremium
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                errorMessage = "Purchase couldn't be completed. Please try again."
                return false
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            return false
        }
    }

    func purchaseWeekly() async -> Bool {
        await purchase(plan: .weekly)
    }

    func purchaseMonthly() async -> Bool {
        await purchase(plan: .monthly)
    }

    func loadProducts() async {
        if isLoadingProducts { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await StoreKit.Product.products(for: candidateProductIds)
            weeklyProduct = pickWeeklyProduct(from: products)
            monthlyProduct = pickMonthlyProduct(from: products)

            if weeklyProduct == nil && monthlyProduct == nil {
                errorMessage = "Subscriptions are temporarily unavailable. Please try again soon."
                return
            }
            errorMessage = nil
        } catch {
            errorMessage = "Subscriptions are temporarily unavailable. Please try again soon."
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed. Please try again."
        }
    }

    func refreshEntitlements() async {
        var activeSnapshot: ActiveSubscriptionSnapshot?
        let validProductIds = Set(candidateProductIds + [weeklyProduct?.id, monthlyProduct?.id].compactMap { $0 })

        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(verificationResult) else { continue }
            guard validProductIds.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }

            let candidate = ActiveSubscriptionSnapshot(
                productId: transaction.productID,
                expiresAt: transaction.expirationDate,
                purchaseDate: transaction.purchaseDate,
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                plan: inferPlan(forProductId: transaction.productID)
            )
            if shouldPrefer(candidate, over: activeSnapshot) {
                activeSnapshot = candidate
            }
        }

        let hasActivePremium = activeSnapshot != nil
        isPremium = hasActivePremium
        SessionManager.shared.isPremium = hasActivePremium
        syncSubscriptionStateToBackend(snapshot: activeSnapshot, isPremium: hasActivePremium)
    }

    private func product(for plan: Plan) -> StoreKit.Product? {
        switch plan {
        case .weekly:
            return weeklyProduct
        case .monthly:
            return monthlyProduct
        }
    }

    private func pickWeeklyProduct(from products: [StoreKit.Product]) -> StoreKit.Product? {
        products.first(where: { $0.id == weeklyProductId })
            ?? products.first(where: { $0.id == defaultWeeklyProductId })
            ?? products.first(where: { $0.id.localizedCaseInsensitiveContains("week") })
    }

    private func pickMonthlyProduct(from products: [StoreKit.Product]) -> StoreKit.Product? {
        products.first(where: { $0.id == monthlyProductId })
            ?? products.first(where: { $0.id == defaultMonthlyProductId })
            ?? products.first(where: { legacyMonthlyProductIds.contains($0.id) })
            ?? products.first(where: { $0.id.localizedCaseInsensitiveContains("month") })
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await verificationResult in Transaction.updates {
                if let transaction = try? checkVerified(verificationResult) {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func inferPlan(forProductId productId: String) -> Plan? {
        if productId == weeklyProduct?.id || productId == weeklyProductId || productId.localizedCaseInsensitiveContains("week") {
            return .weekly
        }
        if productId == monthlyProduct?.id || productId == monthlyProductId || productId.localizedCaseInsensitiveContains("month") {
            return .monthly
        }
        return nil
    }

    private func shouldPrefer(_ candidate: ActiveSubscriptionSnapshot, over current: ActiveSubscriptionSnapshot?) -> Bool {
        guard let current else { return true }

        let candidateExpiry = candidate.expiresAt ?? .distantFuture
        let currentExpiry = current.expiresAt ?? .distantFuture
        if candidateExpiry != currentExpiry {
            return candidateExpiry > currentExpiry
        }
        return candidate.purchaseDate > current.purchaseDate
    }

    private func syncSubscriptionStateToBackend(snapshot: ActiveSubscriptionSnapshot?, isPremium: Bool) {
        guard let userId = SessionManager.shared.userId else { return }

        let signature = snapshot?.signature ?? "inactive"
        if signature == lastSyncedSubscriptionSignature || signature == subscriptionSyncInFlightSignature {
            return
        }

        subscriptionSyncInFlightSignature = signature

        let formatter = ISO8601DateFormatter()
        let payload = SupabaseService.SubscriptionSyncPayload(
            isPremium: isPremium,
            plan: snapshot?.plan?.rawValue,
            productId: snapshot?.productId,
            expiresAt: snapshot?.expiresAt.map { formatter.string(from: $0) },
            lastVerifiedAt: formatter.string(from: Date()),
            transactionId: snapshot?.transactionId,
            originalTransactionId: snapshot?.originalTransactionId,
            environment: nil
        )

        Task.detached(priority: .utility) { [weak self] in
            var didSync = false
            do {
                didSync = try await SupabaseService.shared.syncUserSubscriptionStatus(userId: userId, payload: payload)
            } catch {
                #if DEBUG
                print("⚠️ Subscription sync failed:", error.localizedDescription)
                #endif
            }

            await MainActor.run {
                guard let self else { return }
                if didSync {
                    self.lastSyncedSubscriptionSignature = signature
                }
                if self.subscriptionSyncInFlightSignature == signature {
                    self.subscriptionSyncInFlightSignature = nil
                }
            }
        }
    }
}

private struct ActiveSubscriptionSnapshot {
    let productId: String
    let expiresAt: Date?
    let purchaseDate: Date
    let transactionId: String
    let originalTransactionId: String
    let plan: SubscriptionManager.Plan?

    var signature: String {
        let expirationToken = expiresAt.map { String($0.timeIntervalSince1970) } ?? "none"
        return [productId, expirationToken, transactionId, originalTransactionId].joined(separator: "|")
    }
}

enum StoreError: Error {
    case failedVerification
}
