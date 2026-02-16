import SwiftUI
import PassKit

// ═══════════════════════════════════════════════════
// MARK: - CartView (full page)
// ═══════════════════════════════════════════════════

struct CartView: View {
    @ObservedObject var cartManager: CartManager
    @State private var showingCheckout = false
    @State private var showPaywall = false
    
    var body: some View {
        ZStack {
            PinkDrapeBackground().ignoresSafeArea()
            
            if cartManager.items.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        
                        VStack(spacing: 12) {
                            ForEach(cartManager.items) { item in
                                let pid = item.product.id
                                CartItemCard(
                                    item: item,
                                    onIncrement: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            cartManager.incrementLocal(productId: pid)
                                        }
                                    },
                                    onDecrement: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            cartManager.decrementLocal(productId: pid)
                                        }
                                    },
                                    onRemove: {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        withAnimation(.spring(response: 0.35)) {
                                            cartManager.removeFromCart(productId: pid)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        totalsSection
                            .padding(.top, 20)
                        
                        checkoutButton
                            .padding(.top, 16)
                        
                        Spacer().frame(height: 120)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $showingCheckout) {
            CheckoutView(cartManager: cartManager, total: cartManager.checkoutTotal)
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
        .onDisappear {
            cartManager.flushPendingChanges()
        }
    }
    
    // MARK: Empty
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bag")
                .font(.system(size: 44, weight: .thin))
                .foregroundColor(Color(hex: "D4A0B0"))
            
            Text("Nothing here yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(hex: "3D3D3D"))
            
            Text("Products you add will\nshow up here")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "999999"))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            
            Spacer()
        }
    }
    
    // MARK: Header
    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Cart")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    Text("\(cartManager.itemCount) item\(cartManager.itemCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "999999"))
                }
                Spacer()
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35)) {
                        cartManager.clearCart()
                    }
                }) {
                    Text("Clear all")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            
            // Premium Banner
            if SessionManager.shared.isPremium {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.magnifyingglass")
                    Text("Agent securing best market prices")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "9B6BFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(hex: "F3E5F5"))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                Button(action: { showPaywall = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text("Unlock agent price finding & NA free shipping")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6B9D"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "FFF0F5"))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "FFD1DC"), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
    }

    
    // MARK: Totals
    private var totalsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Subtotal")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                Spacer()
                Text("$\(String(format: "%.2f", cartManager.totalPrice))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "3D3D3D"))
            }
            HStack {
                Text("GlowUp markup")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                Spacer()
                Text("+$\(String(format: "%.2f", cartManager.markupTotal))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "3D3D3D"))
            }
            HStack {
                Text("Shipping")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                Spacer()
                if cartManager.shippingCost == 0 {
                    Text("Free (GlowUp+)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "4ECDC4"))
                } else {
                    Text("$\(String(format: "%.2f", cartManager.shippingCost))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "2D2D2D"))
                }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Total")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Spacer()
                Text("$\(String(format: "%.2f", cartManager.checkoutTotal))")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.85))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: Checkout
    private var checkoutButton: some View {
        Button(action: { showingCheckout = true }) {
            HStack(spacing: 8) {
                Text("Checkout")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "FF6B9D"), Color(hex: "E8507F")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
        }
        .padding(.horizontal, 20)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Cart Item Card
// ═══════════════════════════════════════════════════

struct CartItemCard: View {
    let item: CartItem
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Product Image
            ProductImageView(urlString: item.product.image_url, size: 80)
                .frame(width: 80, height: 80)
                .background(Color(hex: "FFF0F5"))
                .cornerRadius(14)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.brand.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "D4879C"))
                    .tracking(0.4)
                
                Text(item.product.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("$\(item.product.price.roundedUpPriceWithMarkup)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .padding(.top, 2)
            }
            
            Spacer(minLength: 4)
            
            // Qty stepper
            VStack(spacing: 0) {
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "FF6B9D"))
                        .cornerRadius(8, corners: [.topLeft, .topRight])
                }
                
                Text("\(item.quantity)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .frame(width: 30, height: 28)
                    .background(Color.white)
                
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "666666"))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "F0F0F0"))
                        .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "EBEBEB"), lineWidth: 1)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "F0E0E8"), lineWidth: 0.5)
        )
    }
}

// Rounded corner helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Summary Row
// ═══════════════════════════════════════════════════

struct SummaryRow: View {
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "888888"))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(highlight ? Color(hex: "4ECDC4") : Color(hex: "2D2D2D"))
        }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Checkout View
// ═══════════════════════════════════════════════════

struct CheckoutView: View {
    @ObservedObject var cartManager: CartManager
    let total: Double
    @Environment(\.dismiss) private var dismiss
    @State private var orderPlaced = false
    @StateObject private var paymentHandler = PaymentHandler()
    @State private var isAgentBuying = false
    @State private var showAddressAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                PinkDrapeBackground().ignoresSafeArea()
                
                if orderPlaced {
                    orderConfirmationView
                        .transition(.scale.combined(with: .opacity))
                } else if isAgentBuying {
                    agentBuyingView
                } else {
                    checkoutFormView
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
        }
        .alert("Add a shipping address", isPresented: $showAddressAlert) {
            Button("Go to Settings") { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your address isn't set yet. Please add it in Settings → Shipping.")
        }
    }
    
    private var checkoutFormView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                HStack {
                    Text("Total")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Text("$\(String(format: "%.2f", total))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
            .padding(24)
            .background(Color.white.opacity(0.9))
            .cornerRadius(20)
            .padding(.horizontal, 24)
            
            Spacer()
            
            VStack(spacing: 8) {
                ApplePayButton()
                    .frame(height: 52)
                    .onTapGesture { startApplePay() }
                Text("Pay securely with Apple Pay")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "999999"))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    private var agentBuyingView: some View {
        VStack(spacing: 28) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "FF6B9D"))
            
            Text("Purchasing…")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Text("Our agent is securing your items\nfrom the best retailers.")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "888888"))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
        }
    }
    
    private var orderConfirmationView: some View {
        VStack(spacing: 28) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Color(hex: "4ECDC4"))
                .symbolEffect(.bounce, value: orderPlaced)
            
            Text("Order Placed!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Text("Your glow-up is on the way ✨")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "888888"))
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
    }
    
    private func startApplePay() {
        // Flush any pending local qty changes first
        cartManager.flushPendingChanges()
        
        guard SessionManager.shared.hasShippingAddress else {
            showAddressAlert = true
            return
        }
        let purchasedItems = cartManager.items
        paymentHandler.startPayment(items: purchasedItems, total: total) { success in
            if success {
                withAnimation { isAgentBuying = true }
                Task {
                    let userId = SessionManager.shared.userId ?? "guest"
                    let _ = try? await APIService.shared.createOrder(userId: userId, items: purchasedItems)
                    
                    // Integrate each purchased product into the user's routine
                    for item in purchasedItems {
                        try? await APIService.shared.integrateProductIntoRoutine(userId: userId, productId: item.product.id)
                    }
                    
                    try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            isAgentBuying = false
                            orderPlaced = true
                        }
                        cartManager.clearCart()
                    }
                }
            }
        }
    }
}

#Preview {
    let cartManager = CartManager()
    return CartView(cartManager: cartManager)
}
