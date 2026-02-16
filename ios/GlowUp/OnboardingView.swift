import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    let onComplete: (_ userId: String?) -> Void
    @State private var currentImageIndex = 0
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    // Background images
    let backgroundImages = ["welcomebg1", "welcomebg2", "welcomebg3"]
    
    // Rotating Quotes/Subtitles
    let subtitles = [
        "Discover the goddess within you.",
        "Science-backed routines, curated for you.",
        "Your personal AI beauty concierge."
    ]
    
    var body: some View {
        ZStack {
            // MARK: - Rotating Background
            TabView(selection: $currentImageIndex) {
                ForEach(0..<backgroundImages.count, id: \.self) { index in
                    Image(backgroundImages[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill) // Changed to aspectRatio fill
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height) // Explicit full screen frame
                        .clipped()
                        .ignoresSafeArea()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .overlay(
                // Gradient Overlay for Text Readability (Darker at bottom)
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.2),
                        Color(hex: "2D1F3D").opacity(0.8),
                        Color(hex: "1A1225").opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 1.5)) {
                    currentImageIndex = (currentImageIndex + 1) % backgroundImages.count
                }
            }
            
            // MARK: - Content
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                
                // Text Section (approx 2/3 down)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Glow Up\nYour Routine.")
                        .font(.custom("Didot", size: 48)) // Greek/Pink Vibe
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Text(subtitles[currentImageIndex])
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(hex: "FFD4E5")) // Soft Pink
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id("subtitle-\(currentImageIndex)")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Premium preview before post-onboarding mini paywall
                VStack(alignment: .leading, spacing: 8) {
                    Text("GlowUp+ Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "FFD4E5"))
                    HStack(spacing: 10) {
                        Label("Faster AI insights", systemImage: "sparkles")
                        Label("Price scouting", systemImage: "tag.fill")
                        Label("Free shipping", systemImage: "shippingbox.fill")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // Buttons Section
                VStack(spacing: 16) {
                    // Sign In With Apple (Primary) - Official Apple Style
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authResults):
                                handleAuthorization(authResults)
                            case .failure:
                                break
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black) // Official Apple black button
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Secondary Button (Skip/Guest)
                    Button(action: { onComplete(nil) }) {
                        Text("Continue as Guest")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
    }
    
    // Handle Apple Sign In
    func handleAuthorization(_ result: ASAuthorization) {
        if let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential {
            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                return
            }
            
            let fullName = appleIDCredential.fullName
            
            Task {
                do {
                    let user = try await SupabaseService.shared.signInWithApple(identityToken: identityToken, fullName: fullName)
                    
                    if let user = user {
                        SessionManager.shared.saveUser(user)
                        if user.onboarded == true {
                            SessionManager.shared.markOnboarded()
                        }
                    }
                    
                    await MainActor.run { onComplete(user?.id) }
                } catch {
                    await MainActor.run { onComplete(nil) }
                }
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    OnboardingView(onComplete: { _ in })
}
