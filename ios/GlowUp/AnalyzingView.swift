import SwiftUI

struct AnalyzingView: View {
    @Binding var result: AnalysisResult?
    let onComplete: () -> Void
    
    @State private var currentQuoteIndex = 0
    @State private var logoScale: CGFloat = 1.0
    @State private var elapsedTime: Int = 0
    
    private let quotes = [
        "Your skin is your largest organ. Treat it with love.",
        "Consistency beats intensity. Every. Single. Time.",
        "Hydration is the foundation of great skin.",
        "SPF today, thank yourself in 10 years.",
        "Your routine should feel like self-care, not a chore",
        "Good skin is a journey, not a destination.",
        "Listen to your skin—it tells you what it needs",
        "Less is more. Quality over quantity always.",
        "Night time is repair time.",
        "Patience is the ultimate skincare ingredient"
    ]

    private let loadingStages = [
        "Analyzing your profile",
        "Matching products to your skin needs",
        "Building your morning and evening routine"
    ]

    private var currentStage: String {
        let idx = min(elapsedTime / 8, loadingStages.count - 1)
        return loadingStages[idx]
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "FFF0F5"),
                    Color(hex: "FFE8F1")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 92, height: 92)
                        .shadow(color: Color(hex: "FF6B9D").opacity(0.18), radius: 14, x: 0, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                .scaleEffect(logoScale)
                
                VStack(spacing: 12) {
                    Text("Creating your routine")
                        .font(.custom("Didot", size: 32))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    Text(currentStage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "6A6A6A"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                ProgressView()
                    .tint(Color(hex: "FF6B9D"))
                    .scaleEffect(1.1)

                VStack(spacing: 14) {
                    Text(quotes[currentQuoteIndex])
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "4A4A4A"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 30)
                        .id(currentQuoteIndex)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                Text("Usually completes in under 20 seconds.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "8A8A8A"))
                
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
            checkForCompletion()
        }
    }
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            logoScale = 1.06
        }
        
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentQuoteIndex = (currentQuoteIndex + 1) % quotes.count
            }
        }
    }
    
    private func checkForCompletion() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            elapsedTime += 1
            
            if result != nil {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    AnalyzingView(result: .constant(nil), onComplete: {})
}
