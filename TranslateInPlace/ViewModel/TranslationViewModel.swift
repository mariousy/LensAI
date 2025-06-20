import SwiftUI
import Vision
import Translation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import NaturalLanguage

// The ViewModel is the brain of the operation, conforming to @Observable
// to allow SwiftUI views to react to its changes.
@Observable
class TranslationViewModel {
    
    // MARK: - State Management
    
    // Defines the different stages of the translation process.
    enum ProcessingState: Equatable {
        case loadingImage
        case recognizingText
        case translating
        case rendering
        case finished(UIImage)
        case error(String)
        
        // Equatable conformance to allow comparison, especially for the .finished case.
        static func == (lhs: TranslationViewModel.ProcessingState, rhs: TranslationViewModel.ProcessingState) -> Bool {
            switch (lhs, rhs) {
            case (.loadingImage, .loadingImage),
                 (.recognizingText, .recognizingText),
                 (.translating, .translating),
                 (.rendering, .rendering):
                return true
            case (.finished(let img1), .finished(let img2)):
                return img1 === img2
            case (.error(let msg1), .error(let msg2)):
                return msg1 == msg2
            default:
                return false
            }
        }
    }
    
    // Holds the current state of the workflow. SwiftUI views observe this property.
    var processingState: ProcessingState = .loadingImage
    
    // The original image shared by the user.
    var sourceImage: UIImage?
    
    // Configuration for the Translation framework. Setting this triggers the translation task.
    var translationConfiguration: TranslationSession.Configuration?
    
    // The list of languages the user can choose from.
    var availableLanguages: [Locale.Language] = []
    
    // The currently selected target language for translation.
    var targetLanguage: Locale.Language = Locale.current.language
    
    // MARK: - Private Properties

    // The communication channel to the host app.
    private weak var extensionContext: NSExtensionContext?
    
    // FIX: This now stores grouped text data.
    private var groupedTextToTranslate: [GroupedRecognizedText] = []
    
    // Stores the original text recognition results to allow for re-translation.
    private var visionObservations: [VNRecognizedTextObservation] = []
    
    // Stores the final, rendered image.
    private var finalImage: UIImage?
    
    // FIX: A new struct to hold grouped text observations.
    private struct GroupedRecognizedText {
        let combinedText: String
        let combinedBoundingBox: CGRect
    }

    // MARK: - Initialization
    
    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
        
        let languageAvailability = LanguageAvailability()
        Task {
            let allLanguages = await languageAvailability.supportedLanguages
            
            let sortedLanguages = allLanguages.sorted {
                $0.localizedName.compare($1.localizedName) == .orderedAscending
            }
            
            var uniqueLanguages = [Locale.Language]()
            var seenLanguageCodes = Set<String>()
            
            for language in sortedLanguages {
                if let baseCode = language.languageCode?.identifier.components(separatedBy: "-").first {
                    if !seenLanguageCodes.contains(baseCode) {
                        uniqueLanguages.append(language)
                        seenLanguageCodes.insert(baseCode)
                    }
                }
            }
            
            await MainActor.run {
                self.availableLanguages = uniqueLanguages
            }
        }
        
        loadImageFromContext()
    }
    
    // MARK: - Public Interface for View Actions

    func completeExtension() {
        guard let finalImage = self.finalImage else {
            self.processingState = .error("Final image is not available.")
            return
        }
        
        let outputProvider = NSItemProvider(object: finalImage)
        let outputItem = NSExtensionItem()
        outputItem.attachments = [outputProvider]
        
        extensionContext?.completeRequest(returningItems: [outputItem], completionHandler: nil)
    }

    func cancelExtension() {
        let error = NSError(domain: "com.you.ImageTranslator.ErrorDomain", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled."])
        extensionContext?.cancelRequest(withError: error)
    }
    
    // Called by the view when the user selects a new language.
    func retranslate() {
        processRecognitionResults(refiltering: true)
    }
    
    // MARK: - Helper Functions
    
    /// Converts a UIImage.Orientation to a CGImagePropertyOrientation.
    private func cgImageOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    
    /// Resizes an image to a new size only if it's larger than the max dimension.
    private func resizeImage(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        
        let widthRatio  = maxDimension / size.width
        let heightRatio = maxDimension / size.height
        
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let newImage = renderer.image { (context) in
            image.draw(in: rect)
        }
        
        return newImage
    }
    
    // MARK: - Step 1: Load Image
    
    private func loadImageFromContext() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            self.processingState = .error("Could not retrieve image from host app.")
            return
        }

        let imageType = UTType.image.identifier
        if itemProvider.hasItemConformingToTypeIdentifier(imageType) {
            itemProvider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let error = error {
                        self.processingState = .error("Error loading image: \(error.localizedDescription)")
                        return
                    }
                    
                    var image: UIImage?
                    if let url = item as? URL, let imageData = try? Data(contentsOf: url) {
                        image = UIImage(data: imageData)
                    } else if let uiImage = item as? UIImage {
                        image = uiImage
                    } else if let imageData = item as? Data {
                        image = UIImage(data: imageData)
                    }

                    if var initialImage = image {
                        initialImage = self.resizeImage(image: initialImage, maxDimension: 1024)
                        
                        self.sourceImage = initialImage
                        self.processingState = .recognizingText
                        self.recognizeTextInImage(image: initialImage)
                    } else {
                        self.processingState = .error("Could not decode the shared image.")
                    }
                }
            }
        } else {
            self.processingState = .error("Shared item is not a supported image type.")
        }
    }
    
    // MARK: - Step 2: Recognize Text (Vision)
    
    private func recognizeTextInImage(image: UIImage) {
        guard let cgImage = image.cgImage else {
            self.processingState = .error("Failed to get CGImage from source.")
            return
        }

        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            DispatchQueue.main.async {
                self?.processRecognitionResults(request: request, error: error)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImageOrientation(from: image.imageOrientation), options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.processingState = .error("Failed to perform text recognition: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // FIX: This function now includes an intelligent grouping algorithm.
    private func processRecognitionResults(request: VNRequest? = nil, error: Error? = nil, refiltering: Bool = false) {
        if !refiltering {
            guard let results = request?.results as? [VNRecognizedTextObservation], !results.isEmpty else {
                self.processingState = .error("No text was found in the image.")
                return
            }
            self.visionObservations = results
        }
        
        guard let currentImage = self.sourceImage else { return }
        let imageSize = currentImage.size
        
        self.groupedTextToTranslate.removeAll()
        
        // --- TEXT GROUPING LOGIC ---
        
        // 1. Filter out text that doesn't need translation.
        let recognizer = NLLanguageRecognizer()
        let observationsToTranslate = self.visionObservations.filter { observation in
            guard let topCandidate = observation.topCandidates(1).first else { return false }
            recognizer.processString(topCandidate.string)
            guard let sourceNLLanguage = recognizer.dominantLanguage else { return false }
            let sourceLocaleLanguage = Locale.Language(identifier: sourceNLLanguage.rawValue)
            return sourceLocaleLanguage.languageCode != self.targetLanguage.languageCode
        }

        guard !observationsToTranslate.isEmpty else {
            self.processingState = .error("All text is already in your device's language.")
            return
        }
        
        // 2. Sort observations vertically to group lines that are on top of each other.
        let sortedObservations = observationsToTranslate.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        
        var currentGroup = [VNRecognizedTextObservation]()
        var finishedGroups = [[VNRecognizedTextObservation]]()

        for observation in sortedObservations {
            if currentGroup.isEmpty {
                currentGroup.append(observation)
            } else {
                // Heuristic: If the new line is "close" vertically, add it to the group.
                let lastBox = currentGroup.last!.boundingBox
                let verticalDistance = lastBox.minY - observation.boundingBox.maxY
                if verticalDistance < (lastBox.height * 0.5) {
                    currentGroup.append(observation)
                } else {
                    // Otherwise, finish the old group and start a new one.
                    finishedGroups.append(currentGroup)
                    currentGroup = [observation]
                }
            }
        }
        if !currentGroup.isEmpty {
            finishedGroups.append(currentGroup)
        }
        
        // 3. Convert the finalized groups into our data model.
        for group in finishedGroups {
            let combinedText = group.map { $0.topCandidates(1).first!.string }.joined(separator: "\n")
            
            var combinedBox = CGRect.null
            for observation in group {
                let box = VNImageRectForNormalizedRect(observation.boundingBox, Int(imageSize.width), Int(imageSize.height))
                combinedBox = combinedBox.union(box)
            }
            
            let flippedBox = CGRect(x: combinedBox.origin.x, y: imageSize.height - combinedBox.origin.y - combinedBox.height, width: combinedBox.width, height: combinedBox.height)
            
            self.groupedTextToTranslate.append(.init(combinedText: combinedText, combinedBoundingBox: flippedBox))
        }

        self.processingState = .translating
        self.triggerTranslation()
    }

    // MARK: - Step 3: Translate Text (Translation)

    private func triggerTranslation() {
        self.translationConfiguration = TranslationSession.Configuration(target: self.targetLanguage)
    }

    func performTranslation(using session: TranslationSession) async {
        let requests = groupedTextToTranslate.map { TranslationSession.Request(sourceText: $0.combinedText) }
        
        do {
            let responses = try await session.translations(from: requests)
            let translatedStrings = responses.map { $0.targetText }
            
            await MainActor.run {
                self.processingState = .rendering
                self.renderFinalImage(with: translatedStrings)
            }
        } catch {
            await MainActor.run {
                self.processingState = .error("Translation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Step 4: Render Final Image (Core Image & Core Graphics)
    
    private func renderFinalImage(with translatedTexts: [String]) {
        guard let sourceImage = self.sourceImage else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let overallAverageColor = self.getAverageColor(from: sourceImage, in: CGRect(origin: .zero, size: sourceImage.size)) ?? .darkGray
            let uniformBubbleColor = overallAverageColor.lightened()
            let uniformTextColor = uniformBubbleColor.isLight ? UIColor.black : UIColor.white
            
            let renderer = UIGraphicsImageRenderer(size: sourceImage.size)
            let finalImage = renderer.image { context in
                sourceImage.draw(at: .zero)
                
                for (index, group) in self.groupedTextToTranslate.enumerated() {
                    guard index < translatedTexts.count else { continue }
                    
                    let translatedText = translatedTexts[index]
                    let rect = group.combinedBoundingBox
                    
                    let bubblePath = UIBezierPath(roundedRect: rect.insetBy(dx: -8, dy: -4), cornerRadius: 8)
                    uniformBubbleColor.setFill()
                    bubblePath.fill()
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    paragraphStyle.lineBreakMode = .byWordWrapping
                    
                    var fontSize: CGFloat = rect.height / CGFloat(translatedText.components(separatedBy: "\n").count)
                    var font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                    
                    var attributes: [NSAttributedString.Key: Any] = [
                        .paragraphStyle: paragraphStyle,
                        .foregroundColor: uniformTextColor,
                        .font: font
                    ]
                    
                    var attributedText = NSAttributedString(string: translatedText, attributes: attributes)
                    
                    while attributedText.boundingRect(with: rect.size, options: .usesLineFragmentOrigin, context: nil).height > rect.height {
                        fontSize -= 1
                        if fontSize <= 5 { break }
                        font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                        attributes[.font] = font
                        attributedText = NSAttributedString(string: translatedText, attributes: attributes)
                    }
                    
                    let textHeight = attributedText.boundingRect(with: rect.size, options: .usesLineFragmentOrigin, context: nil).height
                    let centeredRect = CGRect(x: rect.origin.x, y: rect.origin.y + (rect.height - textHeight) / 2, width: rect.width, height: textHeight)
                    
                    attributedText.draw(in: centeredRect)
                }
            }

            DispatchQueue.main.async {
                self.finalImage = finalImage
                self.processingState = .finished(finalImage)
            }
        }
    }
    
    // New, robust helper to sample the average color from a region.
    private func getAverageColor(from image: UIImage, in rect: CGRect) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let ciContext = CIContext(options: nil)
        let ciImage = CIImage(cgImage: cgImage)
        let imageBounds = CGRect(origin: .zero, size: image.size)
        let validSampleRect = rect.intersection(imageBounds)

        guard !validSampleRect.isEmpty else { return nil }

        let filter = CIFilter(name: "CIAreaAverage",
                              parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: validSampleRect)])!
        
        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: nil)

        return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: 1.0)
    }
}

// Helper extension to determine if a color is light or dark.
extension UIColor {
    var isLight: Bool {
        guard let components = cgColor.components, components.count > 2 else {
            return false
        }
        let luminance = (0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2])
        return luminance > 0.5
    }
    
    func lightened() -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        if self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let newBrightness = min(brightness + 0.5, 0.95)
            let newSaturation = max(saturation - 0.4, 0.1)
            return UIColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: 1.0)
        }
        
        var white: CGFloat = 0
        if self.getWhite(&white, alpha: &alpha) {
            return UIColor(white: min(white + 0.5, 0.95), alpha: 1.0)
        }
        
        return .systemGray5
    }
}
