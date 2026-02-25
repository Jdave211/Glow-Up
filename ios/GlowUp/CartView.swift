import SwiftUI

// ═══════════════════════════════════════════════════
// MARK: - CartView (full page)
// ═══════════════════════════════════════════════════

struct CartView: View {
    @ObservedObject var cartManager: CartManager
    @State private var showingShopLinks = false
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
        .sheet(isPresented: $showingShopLinks) {
            ShopLinksSheet(items: cartManager.items, subtotal: cartManager.totalPrice)
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
                    Text("Agent compares fit + pricing before you shop")
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
                        Text("Unlock deeper fit scoring + smarter product matching")
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
                Text("Price scouting")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                Spacer()
                Text("Active")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "3D3D3D"))
            }
            HStack {
                Text("Checkout")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "888888"))
                Spacer()
                Text("Direct links")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "2D2D2D"))
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Estimated subtotal")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Spacer()
                Text("$\(String(format: "%.2f", cartManager.totalPrice))")
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
        Button(action: { showingShopLinks = true }) {
            HStack(spacing: 8) {
                Text("Open Purchase Links")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.up.right.square")
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

struct ShopLinksSheet: View {
    let items: [CartItem]
    let subtotal: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var linkedItems: [CartItem] {
        items.filter { ($0.product.buy_link ?? "").isEmpty == false }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("We find you the best skincare from the best and most affordable spots.")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Tap the product links below to buy directly.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "777777"))
                    }
                    .padding(.vertical, 4)
                }

                Section("Products") {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.product.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "2D2D2D"))
                                Text(item.product.brand)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "888888"))
                            }
                            Spacer()
                            if let link = item.product.buy_link,
                               let url = URL(string: link),
                               !link.isEmpty {
                                Button("Open") { openURL(url) }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "FF6B9D"))
                            } else {
                                Text("No link")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "AAAAAA"))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    HStack {
                        Text("Estimated subtotal")
                        Spacer()
                        Text("$\(String(format: "%.2f", subtotal))")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
            .navigationTitle("Shop Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if linkedItems.count > 1 {
                        Button("Open All") {
                            for item in linkedItems {
                                if let link = item.product.buy_link, let url = URL(string: link) {
                                    openURL(url)
                                }
                            }
                        }
                        .foregroundColor(Color(hex: "FF6B9D"))
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Cart Item Card
// ═══════════════════════════════════════════════════

struct CartItemCard: View {
    let item: CartItem
    let onRemove: () -> Void
    @Environment(\.openURL) private var openURL
    
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
                
                Text("$\(item.product.price.roundedUpPrice)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                    .padding(.top, 2)

                if let link = item.product.buy_link,
                   let url = URL(string: link),
                   !link.isEmpty {
                    Button(action: { openURL(url) }) {
                        Label("Open Link", systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "FF6B9D"))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FF6B9D"))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: "FFF0F5"))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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

struct CartView_Previews: PreviewProvider {
    static var previews: some View {
        let cartManager = CartManager()
        return CartView(cartManager: cartManager)
    }
}
