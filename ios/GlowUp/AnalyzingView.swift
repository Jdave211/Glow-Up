import SwiftUI

struct AnalyzingView: View {
    @Binding var result: AnalysisResult?
    let onComplete: () -> Void
    
    @State private var currentQuoteIndex = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var elapsedTime: Int = 0
    @State private var showRetry = false
    
    let quotes = [
        "Your skin is your largest organ—treat it with love 💕",
        "Consistency beats intensity. Every. Single. Time.",
        "Hydration is the foundation of great skin ✨",
        "SPF today, thank yourself in 10 years ☀️",
        "Your routine should feel like self-care, not a chore",
        "Good skin is a journey, not a destination 🌸",
        "Listen to your skin—it tells you what it needs",
        "Less is more. Quality over quantity always.",
        "Night time is repair time 🌙",
        "Patience is the ultimate skincare ingredient"
    ]
    
    var body: some View {
        ZStack {
            // Soft pink gradient background
            LinearGradient(
                colors: [
                    Color(hex: "FFF0F5"),
                    Color(hex: "FFE4EC"),
                    Color(hex: "FFD6E5")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Floating particles
            ForEach(0..<12, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "FF6B9D").opacity(0.1))
                    .frame(width: CGFloat.random(in: 20...60))
                    .offset(
                        x: CGFloat.random(in: -150...150),
                        y: CGFloat.random(in: -300...300)
                    )
                    .blur(radius: 2)
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Animated loading graphic
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(Color(hex: "FF6B9D").opacity(0.2), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                    
                    // Middle rotating ring
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "FF6B9D"), Color(hex: "FFB4C8")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // Inner circle with icon
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color(hex: "FF6B9D").opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Text("✨")
                            .font(.system(size: 36))
                    }
                }
                
                // Title
                VStack(spacing: 12) {
                    Text("Creating Your Routine")
                        .font(.custom("Didot", size: 28))
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "2D2D2D"))
                    
                    Text("Our AI is analyzing your unique profile...")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "666666"))
                }
                
                Spacer()
                
                // Rotating quotes
                VStack(spacing: 16) {
                    Text(quotes[currentQuoteIndex])
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color(hex: "444444"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                        .id(currentQuoteIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    
                    // Quote dots
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            Circle()
                                .fill(i == (currentQuoteIndex % 5) ? Color(hex: "FF6B9D") : Color(hex: "FFB4C8").opacity(0.5))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .frame(height: 100)
                
                Spacer()
                    .frame(height: 60)
                
                // Retry button if taking too long
                if showRetry {
                    VStack(spacing: 12) {
                        Text("Taking longer than expected...")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "888888"))
                        
                        Button(action: {
                            // Force complete even without result
                            onComplete()
                        }) {
                            Text("Continue Anyway")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color(hex: "FF6B9D"))
                                .cornerRadius(12)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .onAppear {
            startAnimations()
            checkForCompletion()
        }
    }
    
    private func startAnimations() {
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        
        // Rotation animation
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        // Quote rotation
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentQuoteIndex = (currentQuoteIndex + 1) % quotes.count
            }
        }
    }
    
    private func checkForCompletion() {
        // Check every 0.5s if result is ready
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            elapsedTime += 1
            
            if result != nil {
                timer.invalidate()
                // Small delay for nice transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onComplete()
                }
            }
            
            // Show retry button after 15 seconds
            if elapsedTime >= 30 && !showRetry {
                withAnimation {
                    showRetry = true
                }
            }
            
            // Auto-continue after 45 seconds ONLY if we have a result
            if elapsedTime >= 90 {
                timer.invalidate()
                if result != nil {
                    onComplete()
                } else {
                    withAnimation {
                        showRetry = true
                    }
                }
            }
        }
    }
}

#Preview {
    AnalyzingView(result: .constant(nil), onComplete: {})
}
