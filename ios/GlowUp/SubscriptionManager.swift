import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var monthlyProduct: StoreKit.Product?
    @Published private(set) var isPremium: Bool = SessionManager.shared.isPremium
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInProgress = false
    @Published var errorMessage: String?

    private let defaultProductId = "com.glowup.premium"
    private let fallbackProductIds = [
        "com.looksmaxx.premium",
        "com.looksmaxx.app.premium"
    ]
    private var updatesTask: Task<Void, Never>?

    var monthlyProductId: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "PREMIUM_MONTHLY_PRODUCT_ID") as? String,
           !fromPlist.isEmpty {
            return fromPlist
        }
        return defaultProductId
    }

    private var candidateProductIds: [String] {
        var ids: [String] = [monthlyProductId]
        if !ids.contains(defaultProductId) {
            ids.append(defaultProductId)
        }
        for fallback in fallbackProductIds where !ids.contains(fallback) {
            ids.append(fallback)
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

    func loadProducts() async {
        if isLoadingProducts { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let ids = candidateProductIds
            let products = try await StoreKit.Product.products(for: ids)
            monthlyProduct =
                products.first(where: { $0.id == monthlyProductId }) ??
                products.first(where: { $0.id == defaultProductId }) ??
                products.first
            if monthlyProduct == nil {
                errorMessage = "Subscription product unavailable. Verify the App Store product ID."
                return
            }
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load subscription products. Please try again."
        }
    }

    func purchaseMonthly() async -> Bool {
        errorMessage = nil

        if monthlyProduct == nil {
            await loadProducts()
        }
        guard let product = monthlyProduct else {
            let ids = candidateProductIds.joined(separator: ", ")
            errorMessage = "Subscription product unavailable right now. Configured IDs: \(ids)"
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
                errorMessage = "Unknown purchase result."
                return false
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            return false
        }
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Could not restore purchases."
        }
    }

    func refreshEntitlements() async {
        var hasActivePremium = false
        let validProductIds = Set(candidateProductIds + [monthlyProduct?.id].compactMap { $0 })

        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(verificationResult) else { continue }
            if validProductIds.contains(transaction.productID) && transaction.revocationDate == nil {
                if let expirationDate = transaction.expirationDate {
                    hasActivePremium = expirationDate > Date()
                } else {
                    hasActivePremium = true
                }
            }
            if hasActivePremium { break }
        }

        isPremium = hasActivePremium
        SessionManager.shared.isPremium = hasActivePremium
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
}

enum StoreError: Error {
    case failedVerification
}
