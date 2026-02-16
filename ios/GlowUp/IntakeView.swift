import SwiftUI
import PhotosUI

struct IntakeView: View {
    @Binding var profile: UserProfile
    let onAnalyze: () -> Void
    let onBack: () -> Void
    
    @State private var currentStep = 0
    @State private var scrollID = UUID()
    // Total steps: 0 (Photo), 1 (Skin 1), 2 (Skin 2), 3 (Hair - optional), 4 (Lifestyle/Reminders)
    private let totalSteps = 5
    private let stepTitles = [
        "Add your photos",
        "Skin basics",
        "Skin goals",
        "Hair",
        "Lifestyle & reminders"
    ]
    private let stepSubtitles = [
        "Optional, but improves accuracy dramatically.",
        "Tell us about your skin type and tone.",
        "What do you want to improve most?",
        "Optional — helps us refine your full routine.",
        "Set preferences that shape your routine."
    ]
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header / Progress
                HStack {
                    Button(action: {
                        if currentStep > 0 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { 
                                currentStep -= 1
                                scrollID = UUID() // Reset scroll
                            }
                        } else {
                            onBack()
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: "2D2D2D"))
                    }
                    
                    Spacer()
                    
                    // Progress Indicator
                    HStack(spacing: 4) {
                        ForEach(0..<totalSteps, id: \.self) { index in
                            Capsule()
                                .fill(index <= currentStep ? Color(hex: "FF6B9D") : Color(hex: "E5E7EB"))
                                .frame(width: index == currentStep ? 24 : 16, height: 4)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    // Step counter
                    Text("\(currentStep + 1)/\(totalSteps)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "999999"))
                        .frame(width: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                
                // Content
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            Color.clear.frame(height: 1).id("top")

                            VStack(alignment: .leading, spacing: 8) {
                                Text(stepTitles[currentStep])
                                    .font(.custom("Didot", size: 28))
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(hex: "2D2D2D"))
                                Text(stepSubtitles[currentStep])
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "888888"))
                            }
                            
                            switch currentStep {
                            case 0:
                                PhotoUploadStep(profile: $profile, onContinue: { 
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { 
                                        currentStep += 1
                                        scrollID = UUID()
                                    }
                                })
                            case 1:
                                SkinBasicsStep(profile: $profile)
                            case 2:
                                SkinGoalsStep(profile: $profile)
                            case 3:
                                HairStep(profile: $profile, onSkip: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        currentStep += 1
                                        scrollID = UUID()
                                    }
                                })
                            case 4:
                                RemindersStep(profile: $profile)
                            default:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 120)
                    }
                    .onChange(of: scrollID) { _, _ in
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
                
                // Footer Buttons (except for photo step which has its own)
                if currentStep != 0 {
                    VStack(spacing: 0) {
                        Divider()
                            .background(Color(hex: "F0F0F0"))
                        
                        Button(action: {
                            if currentStep < totalSteps - 1 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { 
                                    currentStep += 1
                                    scrollID = UUID() // Reset scroll
                                }
                            } else {
                                onAnalyze()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text(currentStep == totalSteps - 1 ? "Finish & Generate Routine" : "Continue")
                                    .font(.system(size: 17, weight: .semibold))
                                if currentStep == totalSteps - 1 {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "2D2D2D")) // Dark button - different from selections
                            .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                    .background(Color.white)
                }
            }
        }
    }
}

// MARK: - Step 1: Photo Upload
struct PhotoUploadStep: View {
    @Binding var profile: UserProfile
    let onContinue: () -> Void
    
    @State private var showingSlotOptions = false
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var frontImage: UIImage? = nil
    @State private var leftImage: UIImage? = nil
    @State private var rightImage: UIImage? = nil
    @State private var scalpImage: UIImage? = nil
    @State private var selectedSlot: Int = 0 // 0=front, 1=left, 2=right, 3=scalp
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isLoading = false
    @State private var didHydratePhotosFromProfile = false
    
    var photoCount: Int {
        [frontImage, leftImage, rightImage, scalpImage].compactMap { $0 }.count
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with icon
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FFF0F5"))
                        .frame(width: 64, height: 64)
                    Text("📸")
                        .font(.system(size: 28))
                }
                
                Text("Add Your Photos")
                    .font(.custom("Didot", size: 28))
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                Text("Recommended for **85% more accurate** results")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "666666"))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            
            // Photo Grid - Each slot is individually tappable
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PhotoSlotButton(
                    label: "Front",
                    icon: "face.smiling",
                    image: frontImage,
                    isLoading: isLoading && selectedSlot == 0
                ) {
                    selectedSlot = 0
                    showingSlotOptions = true
                }
                
                PhotoSlotButton(
                    label: "Left Side",
                    icon: "person.fill.viewfinder",
                    image: leftImage,
                    isLoading: isLoading && selectedSlot == 1
                ) {
                    selectedSlot = 1
                    showingSlotOptions = true
                }
                
                PhotoSlotButton(
                    label: "Right Side",
                    icon: "person.fill.viewfinder",
                    image: rightImage,
                    flipped: true,
                    isLoading: isLoading && selectedSlot == 2
                ) {
                    selectedSlot = 2
                    showingSlotOptions = true
                }
                
                PhotoSlotButton(
                    label: "Hair/Scalp",
                    icon: "sparkles",
                    image: scalpImage,
                    isLoading: isLoading && selectedSlot == 3
                ) {
                    selectedSlot = 3
                    showingSlotOptions = true
                }
            }
            
            // Tips Row
            HStack(spacing: 0) {
                MiniTip(icon: "sun.max.fill", text: "Natural light")
                Spacer()
                MiniTip(icon: "face.dashed", text: "No makeup")
                Spacer()
                MiniTip(icon: "camera.fill", text: "Eye level")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "F8F8F8"))
            .cornerRadius(12)
            
            Text("Tap any tile to add from your library or camera.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "888888"))
                .multilineTextAlignment(.center)

            // Next button
            VStack(spacing: 12) {
                Button(action: {
                    syncProfilePhotos()
                    onContinue()
                }) {
                    Text(photoCount == 4 ? "Continue with 4 photos →" : "Next →")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                .padding(.top, 4)
            }
            
            // Privacy Badge
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "4ADE80"))
                Text("Private visual history is on by default. You can opt out anytime.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "666666"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(hex: "F0FDF4"))
            .cornerRadius(12)
        }
        .confirmationDialog("Add photo", isPresented: $showingSlotOptions, titleVisibility: .visible) {
            Button("Choose from Library") {
                showingPhotoLibrary = true
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    showingCamera = true
                }
            }
            if imageForSelectedSlot() != nil {
                Button("Remove Photo", role: .destructive) {
                    setImageForSelectedSlot(nil)
                    syncProfilePhotos()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how you want to add this photo.")
        }
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $selectedItem, matching: .images)
        .onAppear {
            guard !didHydratePhotosFromProfile else { return }
            hydratePhotoStateFromProfile()
            didHydratePhotosFromProfile = true
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            isLoading = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            setImageForSelectedSlot(image)
                        }
                        syncProfilePhotos()
                        isLoading = false
                        selectedItem = nil
                        advanceToNextEmptySlot()
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                        selectedItem = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { image in
                if let image {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        setImageForSelectedSlot(image)
                    }
                    syncProfilePhotos()
                    advanceToNextEmptySlot()
                }
            }
        }
    }
    
    private func advanceToNextEmptySlot() {
        if frontImage == nil { selectedSlot = 0 }
        else if leftImage == nil { selectedSlot = 1 }
        else if rightImage == nil { selectedSlot = 2 }
        else if scalpImage == nil { selectedSlot = 3 }
    }

    private func imageForSelectedSlot() -> UIImage? {
        switch selectedSlot {
        case 0: return frontImage
        case 1: return leftImage
        case 2: return rightImage
        case 3: return scalpImage
        default: return nil
        }
    }

    private func setImageForSelectedSlot(_ image: UIImage?) {
        switch selectedSlot {
        case 0: frontImage = image
        case 1: leftImage = image
        case 2: rightImage = image
        case 3: scalpImage = image
        default: break
        }
    }

    private func syncProfilePhotos() {
        var encoded: [String] = []
        if let frontImage, let payload = encodeImagePayload(frontImage) { encoded.append("front:\(payload)") }
        if let leftImage, let payload = encodeImagePayload(leftImage) { encoded.append("left:\(payload)") }
        if let rightImage, let payload = encodeImagePayload(rightImage) { encoded.append("right:\(payload)") }
        if let scalpImage, let payload = encodeImagePayload(scalpImage) { encoded.append("scalp:\(payload)") }
        profile.photos = encoded
    }

    private func hydratePhotoStateFromProfile() {
        guard !profile.photos.isEmpty else { return }

        for entry in profile.photos {
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let slot = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let payload = String(parts[1])
            guard let image = decodeImagePayload(payload) else { continue }

            switch slot {
            case "front":
                frontImage = image
            case "left":
                leftImage = image
            case "right":
                rightImage = image
            case "scalp":
                scalpImage = image
            default:
                continue
            }
        }
    }

    private func decodeImagePayload(_ payload: String) -> UIImage? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let base64String: String
        if trimmed.starts(with: "data:") {
            guard let commaIndex = trimmed.firstIndex(of: ",") else { return nil }
            base64String = String(trimmed[trimmed.index(after: commaIndex)...])
        } else {
            base64String = trimmed
        }

        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func encodeImagePayload(_ image: UIImage) -> String? {
        let resized = resizedImageIfNeeded(image, maxDimension: 1280)
        guard let jpegData = resized.jpegData(compressionQuality: 0.75) else { return nil }
        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    private func resizedImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let currentMax = max(size.width, size.height)
        guard currentMax > maxDimension else { return image }

        let scale = maxDimension / currentMax
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - Review Step
struct ReviewStep: View {
    @Binding var profile: UserProfile
    
    private var parsed: UserProfile { profile.normalized() }
    
    var body: some View {
        VStack(spacing: 18) {
            ReviewCard(title: "Skin Profile") {
                ReviewRow(label: "Skin type", value: parsed.skinType.capitalized)
                ReviewRow(label: "Skin tone", value: SkinToneInfo.label(for: parsed.skinTone))
                ReviewRow(label: "Goals", value: parsed.skinGoals.isEmpty ? "Not set" : parsed.skinGoals.joined(separator: ", "))
                ReviewRow(label: "Concerns", value: parsed.concerns.isEmpty ? "Not set" : parsed.concerns.joined(separator: ", "))
            }
            
            if !parsed.hairType.isEmpty || !parsed.washFrequency.isEmpty {
                ReviewCard(title: "Hair Profile") {
                    ReviewRow(label: "Hair type", value: parsed.hairType.isEmpty ? "Skipped" : parsed.hairType.capitalized)
                    ReviewRow(label: "Wash frequency", value: parsed.washFrequency.isEmpty ? "Skipped" : parsed.washFrequency.replacingOccurrences(of: "_", with: " "))
                }
            } else {
                ReviewCard(title: "Hair Profile") {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "999999"))
                        Text("Skipped — you can add this later in settings.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "888888"))
                    }
                }
            }
            
            ReviewCard(title: "Preferences") {
                ReviewRow(label: "Budget", value: parsed.budget.capitalized)
                ReviewRow(label: "Fragrance‑free", value: parsed.fragranceFree ? "Yes" : "No")
                ReviewRow(label: "Reminders", value: parsed.routineReminders ? "On" : "Off")
                ReviewRow(label: "Photo check‑ins", value: parsed.photoCheckIns ? "On" : "Off")
            }
            
            Text("We’ll use this to generate your personalized routine and product matches.")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "888888"))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }
}

struct ReviewCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

struct ReviewRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "888888"))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "2D2D2D"))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct MiniTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "FF6B9D"))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "666666"))
        }
    }
}

struct PhotoSlotButton: View {
    let label: String
    let icon: String
    var image: UIImage? = nil
    var flipped: Bool = false
    var isLoading: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(
                            ZStack {
                                // Dark overlay for text readability
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .cornerRadius(12)
                                
                                VStack {
                                    // Checkmark badge
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Color(hex: "4ADE80"))
                                            .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                                            .padding(8)
                                    }
                                    Spacer()
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(6)
                                        .padding(6)
                                }
                            }
                        )
                } else if isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(hex: "FF6B9D"))
                        Text("Loading...")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "999999"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color(hex: "FFF0F5"))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "FF6B9D").opacity(0.5), lineWidth: 2)
                    )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "FFB4C8"))
                            .scaleEffect(x: flipped ? -1 : 1, y: 1)
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "888888"))
                        Text("Tap to add")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "AAAAAA"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color(hex: "FFF8FA"))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "FFE4EC"), lineWidth: 1.5)
                    )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PhotoSlot: View {
    let label: String
    let icon: String
    var image: UIImage? = nil
    var flipped: Bool = false
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 100)
                    .clipped()
                    .cornerRadius(12)
                    .overlay(
                        VStack {
                            Spacer()
                            Text(label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                                .padding(6)
                        }
                    )
            } else {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "FFB4C8"))
                        .scaleEffect(x: flipped ? -1 : 1, y: 1)
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "888888"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(Color(hex: "FFF8FA"))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .foregroundColor(Color(hex: "FFE4EC"))
                )
            }
        }
    }
}


// MARK: - Camera Capture
struct CameraCaptureView: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.onFinish(image)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
            parent.dismiss()
        }
    }
}

// MARK: - Step 2: Skin Basics (Type + Tone + Sunscreen)
struct SkinBasicsStep: View {
    @Binding var profile: UserProfile
    
    let skinTypes = ["Normal", "Oily", "Dry", "Combination", "Sensitive"]
    private let customSkinTypeMaxChars = 28
    @State private var customSkinType = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            QuestionHeader(
                title: "Skin Basics",
                subtitle: "Let's understand your skin better."
            )
            
            // Q1: Skin Type
            VStack(alignment: .leading, spacing: 14) {
                Text("How would you describe your skin?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                FlowLayout(spacing: 10) {
                    ForEach(skinTypes, id: \.self) { type in
                        SoftChip(
                            text: type,
                            isSelected: profile.skinType == type.lowercased(),
                            action: {
                                profile.skinType = type.lowercased()
                                customSkinType = ""
                            }
                        )
                    }
                }

                SoftInputChip(
                    placeholder: "Other (optional)",
                    text: $customSkinType,
                    maxChars: customSkinTypeMaxChars
                )
            }
            
            // Q2: Skin Tone Slider
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your skin tone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                    Spacer()
                    Text(SkinToneInfo.label(for: profile.skinTone))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
                
                SkinToneSlider(value: $profile.skinTone)
                
                Text("Helps us recommend products suited for your melanin level")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "999999"))
            }
            
            // Q3: Sunscreen
            VStack(alignment: .leading, spacing: 14) {
                Text("Do you use sunscreen?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                VStack(spacing: 10) {
                    SoftOptionButton(
                        text: "Yes, daily",
                        emoji: "☀️",
                        isSelected: profile.sunscreenUsage == "daily"
                    ) {
                        profile.sunscreenUsage = "daily"
                    }
                    SoftOptionButton(
                        text: "Sometimes",
                        emoji: "🌤️",
                        isSelected: profile.sunscreenUsage == "sometimes"
                    ) {
                        profile.sunscreenUsage = "sometimes"
                    }
                    SoftOptionButton(
                        text: "Rarely or never",
                        emoji: "🌙",
                        isSelected: profile.sunscreenUsage == "rarely"
                    ) {
                        profile.sunscreenUsage = "rarely"
                    }
                }
                
                if profile.sunscreenUsage != "daily" {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "FFB020"))
                        Text("Daily SPF 30+ is the most effective anti-aging product for all skin tones.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "666666"))
                    }
                    .padding(12)
                    .background(Color(hex: "FFFBEB"))
                    .cornerRadius(10)
                }
            }
        }
        .onAppear {
            // If previously saved value isn't one of the standard chips, prefill custom input.
            let standard = Set(skinTypes.map { $0.lowercased() })
            if !profile.skinType.isEmpty && !standard.contains(profile.skinType.lowercased()) {
                customSkinType = profile.skinType
            }
        }
        .onChange(of: customSkinType) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                profile.skinType = trimmed.lowercased()
            }
        }
    }
}

// MARK: - Skin Tone Slider Component
struct SkinToneSlider: View {
    @Binding var value: Double
    
    let toneColors: [Color] = [
        Color(hex: "FFE4D6"),
        Color(hex: "F5D0C5"),
        Color(hex: "E8B894"),
        Color(hex: "D4A574"),
        Color(hex: "C68642"),
        Color(hex: "8D5524"),
        Color(hex: "5C3A21"),
        Color(hex: "3D2314")
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Color bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Gradient track
                    LinearGradient(
                        colors: toneColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 24)
                    .cornerRadius(12)
                    
                    // Thumb
                    Circle()
                        .fill(Color(hex: SkinToneInfo.color(for: value)))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                        .offset(x: CGFloat(value) * (geometry.size.width - 32))
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newValue = gesture.location.x / geometry.size.width
                                    value = min(max(0, newValue), 1)
                                }
                        )
                }
            }
            .frame(height: 32)
            
            // Labels
            HStack {
                Text("Fair")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "999999"))
                Spacer()
                Text("Deep")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "999999"))
            }
        }
    }
}

// MARK: - Step 3: Skin Goals (Deep Dive + Goals)
struct SkinGoalsStep: View {
    @Binding var profile: UserProfile
    @State private var customConcern = ""
    private let customConcernMaxChars = 32
    
    let concerns = ["Acne", "Aging", "Dark Spots", "Texture", "Redness", "Dryness"]
    
    let skinGoals: [(id: String, emoji: String, title: String, desc: String)] = [
        ("glass_skin", "✨", "Glass Skin", "Dewy, translucent glow"),
        ("clear_skin", "🪞", "Clear & Clean", "Minimize breakouts & pores"),
        ("brightening", "🌟", "Brightening", "Even tone, radiant finish"),
        ("anti_aging", "🌿", "Youthful Glow", "Firmness & fine line care"),
        ("barrier_repair", "🛡️", "Barrier Repair", "Strengthen & soothe"),
        ("natural_minimal", "🍃", "Natural Minimal", "Simple, healthy skin")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            QuestionHeader(
                title: "Skin Goals",
                subtitle: "What does your ideal skin look like?"
            )
            
            // Skin Goals Grid
            VStack(alignment: .leading, spacing: 14) {
                Text("I'm working towards...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(skinGoals, id: \.id) { goal in
                        SkinGoalCard(
                            emoji: goal.emoji,
                            title: goal.title,
                            desc: goal.desc,
                            isSelected: profile.skinGoals.contains(goal.id)
                        ) {
                            if profile.skinGoals.contains(goal.id) {
                                profile.skinGoals.removeAll { $0 == goal.id }
                            } else if profile.skinGoals.count < 2 {
                                profile.skinGoals.append(goal.id)
                            }
                        }
                    }
                }
                
                if profile.skinGoals.count > 0 {
                    Text("Selected: \(profile.skinGoals.count)/2")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
            
            // Concerns
            VStack(alignment: .leading, spacing: 14) {
                Text("Any specific concerns?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                FlowLayout(spacing: 10) {
                    ForEach(concerns, id: \.self) { concern in
                        SoftChip(
                            text: concern,
                            isSelected: profile.concerns.contains(concern.lowercased()),
                            action: {
                                let key = concern.lowercased()
                                if profile.concerns.contains(key) {
                                    profile.concerns.removeAll { $0 == key }
                                } else {
                                    profile.concerns.append(key)
                                }
                            }
                        )
                    }
                }

                HStack(spacing: 10) {
                    SoftInputChip(
                        placeholder: "Add custom concern",
                        text: $customConcern,
                        maxChars: customConcernMaxChars
                    )

                    Button(action: addCustomConcern) {
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "D64D7A"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(hex: "FFF5F8"))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "FF6B9D"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Sensitivities
            SoftToggleRow(
                text: "Fragrance-free preferred",
                icon: "leaf",
                isOn: $profile.fragranceFree
            )
        }
    }

    private func addCustomConcern() {
        let trimmed = customConcern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.lowercased().replacingOccurrences(of: " ", with: "_")
        if !profile.concerns.contains(normalized) {
            profile.concerns.append(normalized)
        }
        customConcern = ""
    }
}

struct SkinGoalCard: View {
    let emoji: String
    let title: String
    let desc: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(emoji)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "D64D7A") : Color(hex: "2D2D2D"))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "888888"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? Color(hex: "FFF5F8") : Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "FF6B9D") : Color(hex: "F0F0F0"), lineWidth: isSelected ? 1.5 : 1)
            )
        }
    }
}

// MARK: - Step 4: Hair (Optional, single page)
struct HairStep: View {
    @Binding var profile: UserProfile
    let onSkip: () -> Void
    
    let hairTypes = ["Straight", "Wavy", "Curly", "Coily"]
    
    let washOptions: [(id: String, label: String)] = [
        ("daily", "Daily"),
        ("2_3_weekly", "2-3x/week"),
        ("weekly", "Weekly"),
        ("biweekly", "Biweekly"),
        ("monthly", "Monthly or less")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hair Texture
            VStack(alignment: .leading, spacing: 12) {
                Text("Hair texture")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                FlowLayout(spacing: 10) {
                    ForEach(hairTypes, id: \.self) { type in
                        SoftChip(
                            text: type,
                            isSelected: profile.hairType == type.lowercased(),
                            action: { profile.hairType = type.lowercased() }
                        )
                    }
                }
            }
            
            // Wash Frequency — compact chip style
            VStack(alignment: .leading, spacing: 12) {
                Text("Wash frequency")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                FlowLayout(spacing: 10) {
                    ForEach(washOptions, id: \.id) { option in
                        SoftChip(
                            text: option.label,
                            isSelected: profile.washFrequency == option.id,
                            action: { profile.washFrequency = option.id }
                        )
                    }
                }
            }
            
            // Skip nudge
            Button(action: onSkip) {
                HStack(spacing: 6) {
                    Text("Skip hair for now")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(hex: "999999"))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Step 6: Budget & Reminders
struct RemindersStep: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            QuestionHeader(
                title: "Final Touches",
                subtitle: "Budget and how we can help you stay on track."
            )
            
            // Budget
            VStack(alignment: .leading, spacing: 14) {
                Text("Monthly beauty budget")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                
                HStack(spacing: 10) {
                    BudgetCard(label: "$", range: "<$40", isSelected: profile.budget == "low") {
                        profile.budget = "low"
                    }
                    BudgetCard(label: "$$", range: "$40-80", isSelected: profile.budget == "medium") {
                        profile.budget = "medium"
                    }
                    BudgetCard(label: "$$$", range: "$80+", isSelected: profile.budget == "high") {
                        profile.budget = "high"
                    }
                }
            }
            
            // Reminders Section
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "FF6B9D"))
                    Text("Stay consistent")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "2D2D2D"))
                }
                
                // Routine Reminders
                VStack(spacing: 12) {
                    ReminderToggleCard(
                        icon: "sparkles",
                        title: "Routine reminders",
                        desc: "Gentle nudges to do your AM/PM routine",
                        isOn: $profile.routineReminders
                    )
                    
                    ReminderToggleCard(
                        icon: "camera",
                        title: "Progress check-ins",
                        desc: "Biweekly photo uploads to track & adjust recommendations",
                        isOn: $profile.photoCheckIns
                    )
                }
            }
            
            // Info note
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "FF6B9D"))
                Text("We'll use your check-ins to refine product suggestions—recommending what works, replacing what doesn't.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "666666"))
                    .lineSpacing(3)
            }
            .padding(14)
            .background(Color(hex: "FFF5F8"))
            .cornerRadius(12)
        }
    }
}

struct BudgetCard: View {
    let label: String
    let range: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(isSelected ? Color(hex: "D64D7A") : Color(hex: "2D2D2D"))
                Text(range)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "888888"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isSelected ? Color(hex: "FFF5F8") : Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "FF6B9D") : Color(hex: "F0F0F0"), lineWidth: isSelected ? 1.5 : 1)
            )
        }
    }
}

struct ReminderToggleCard: View {
    let icon: String
    let title: String
    let desc: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FFF0F5"))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "2D2D2D"))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "888888"))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color(hex: "FF6B9D"))
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "F0F0F0"), lineWidth: 1)
        )
    }
}

// MARK: - Shared Components

struct QuestionHeader: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("Didot", size: 28))
                .fontWeight(.bold)
                .foregroundColor(Color(hex: "2D2D2D"))
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "888888"))
        }
    }
}

// Soft rounded chip (for type selections)
struct SoftChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? Color(hex: "D64D7A") : Color(hex: "555555"))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(isSelected ? Color(hex: "FFE8F0") : Color.white)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(isSelected ? Color(hex: "FF6B9D") : Color(hex: "E8E8E8"), lineWidth: isSelected ? 1.5 : 1)
                )
        }
    }
}

// Mini text input styled to match option chips/cards
struct SoftInputChip: View {
    let placeholder: String
    @Binding var text: String
    let maxChars: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "999999"))

            TextField(placeholder, text: $text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "444444"))
                .autocapitalization(.words)
                .disableAutocorrection(true)

            Text("\(text.count)/\(maxChars)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "AAAAAA"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "E8E8E8"), lineWidth: 1)
        )
        .onChange(of: text) { _, newValue in
            if newValue.count > maxChars {
                text = String(newValue.prefix(maxChars))
            }
        }
    }
}

// Soft option button with emoji (for sunscreen etc)
struct SoftOptionButton: View {
    let text: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 18))
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "D64D7A") : Color(hex: "444444"))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "FF6B9D"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color(hex: "FFF5F8") : Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color(hex: "FF6B9D") : Color(hex: "EEEEEE"), lineWidth: isSelected ? 1.5 : 1)
            )
        }
    }
}

// Soft toggle row
struct SoftToggleRow: View {
    let text: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FFF0F5"))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "FF6B9D"))
            }
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "2D2D2D"))
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color(hex: "FF6B9D"))
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "F0F0F0"), lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    IntakeView(
        profile: .constant(UserProfile()),
        onAnalyze: {},
        onBack: {}
    )
}
