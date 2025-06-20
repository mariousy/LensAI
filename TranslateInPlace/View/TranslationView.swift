import SwiftUI
import Translation

// This is the main user interface for the extension.
// It observes the ViewModel and renders the UI based on the current processing state.
struct TranslationView: View {
    
    // @State is the correct property wrapper when a view receives an
    // already-initialized @Observable object.
    @State var viewModel: TranslationViewModel

    var body: some View {
        // A ZStack allows us to overlay views, perfect for showing a progress
        // indicator over the original image.
        ZStack {
            // Main content area that switches based on the processing state.
            VStack(spacing: 0) {
                // The switch statement is the core of this reactive UI.
                // It ensures the view always reflects the current state of the ViewModel.
                switch viewModel.processingState {
                case .loadingImage:
                    Spacer()
                    ProgressView { Text("Loading Image...") }
                    Spacer()
                
                case .recognizingText:
                    contentView(with: "Recognizing Text...")
                
                case .translating:
                    contentView(with: "Translating...")
                    
                case .rendering:
                    contentView(with: "Applying Translation...")

                case .finished(let finalImage):
                    // Display the final, translated image.
                    Image(uiImage: finalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // --- UI REFINEMENT ---
                    // This section has been redesigned for a cleaner, more professional look.
                    VStack(spacing: 15) {
                        // FIX: Replaced Picker with a Menu for a better button-like interaction.
                        Menu {
                            ForEach(viewModel.availableLanguages) { language in
                                Button(language.localizedName) {
                                    viewModel.targetLanguage = language
                                }
                            }
                        } label: {
                            HStack {
                                Text("Translate to:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.targetLanguage.localizedName)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        }
                        
                        // FIX: Buttons are now sized based on their content for a more balanced look.
                        HStack(spacing: 15) {
                            Button("Cancel") {
                                viewModel.cancelExtension()
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical)
                            .background(.quaternary)
                            .foregroundColor(.primary)
                            .clipShape(Capsule())
                            
                            Button("Save & Close") {
                                viewModel.completeExtension()
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .padding()

                case .error(let message):
                    // Display an error message if something went wrong.
                    Spacer()
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(message)
                            .padding()
                            .multilineTextAlignment(.center)
                        Button("Dismiss") {
                            viewModel.cancelExtension()
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        // This modifier listens for changes to the `translationConfiguration`
        // in the ViewModel and provides a `TranslationSession` when it's set.
        .translationTask(viewModel.translationConfiguration) { session in
            Task {
                await viewModel.performTranslation(using: session)
            }
        }
        // This modifier detects when the user chooses a new language
        // and calls the retranslate() method.
        .onChange(of: viewModel.targetLanguage) {
            viewModel.retranslate()
        }
    }
    
    // A helper function to reduce code duplication for the progress states.
    // It shows the source image with a progress indicator overlaid.
    @ViewBuilder
    private func contentView(with status: String) -> some View {
        if let sourceImage = viewModel.sourceImage {
            Image(uiImage: sourceImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    VStack {
                        ProgressView()
                            .padding()
                            .background(.regularMaterial)
                            .cornerRadius(10)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
        } else {
            // Fallback if the source image isn't loaded yet.
            Spacer()
            ProgressView { Text(status) }
            Spacer()
        }
    }
}

// Add this extension to make Locale.Language identifiable for the Picker
extension Locale.Language: Identifiable {
    public var id: Int { self.hashValue }
}

// Helper property to get the localized name of a language.
extension Locale.Language {
    var localizedName: String {
        Locale.current.localizedString(forIdentifier: self.languageCode?.identifier ?? "") ?? "Unknown Language"
    }
}
