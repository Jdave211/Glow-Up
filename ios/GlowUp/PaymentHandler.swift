import SwiftUI
import PassKit

// MARK: - Payment Manager
class PaymentHandler: NSObject, ObservableObject {
    @Published var paymentStatus: PKPaymentAuthorizationStatus = .failure
    @Published var isProcessing = false
    
    typealias PaymentCompletion = (Bool) -> Void
    var completionHandler: PaymentCompletion?
    
    func startPayment(items: [CartItem], total: Double, completion: @escaping PaymentCompletion) {
        self.completionHandler = completion
        self.isProcessing = true
        
        let request = PKPaymentRequest()
        request.merchantIdentifier = "merchant.com.glowup.app" // Replace with your merchant ID
        request.supportedNetworks = [.visa, .masterCard, .amex]
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        
        // Add base items (DB prices)
        var summaryItems = items.map { item in
            PKPaymentSummaryItem(
                label: "\(item.product.name) (x\(item.quantity))",
                amount: NSDecimalNumber(value: item.product.price * Double(item.quantity))
            )
        }
        
        // App-only markup: $1 per product unit (not persisted in DB prices)
        let totalUnits = items.reduce(0) { $0 + $1.quantity }
        let markupAmount = Double(totalUnits) * Double.appUnitMarkup
        let markup = PKPaymentSummaryItem(label: "GlowUp markup", amount: NSDecimalNumber(value: markupAmount))
        summaryItems.append(markup)
        
        // Total
        let totalAmount = NSDecimalNumber(value: total)
        summaryItems.append(PKPaymentSummaryItem(label: "GlowUp Total", amount: totalAmount))
        
        request.paymentSummaryItems = summaryItems
        
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        
        controller.present { presented in
            if !presented {
                #if DEBUG
                print("❌ Failed to present Apple Pay")
                #endif
                self.isProcessing = false
                completion(false)
            }
        }
    }
}

extension PaymentHandler: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        // Send the payment token to backend for processing
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            self.paymentStatus = .success
        }
    }
    
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.completionHandler?(self.paymentStatus == .success)
            }
        }
    }
}

// MARK: - Apple Pay Button Wrapper
struct ApplePayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> PKPaymentButton {
        return PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}
}

// MARK: - Update Cart View Logic
// (I will update the CheckoutView in CartView.swift directly via search_replace)



