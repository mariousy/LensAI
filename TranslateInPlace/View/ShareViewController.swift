import UIKit
import SwiftUI

// This is the entry point for the Share Extension.
// Its primary responsibility is to host our SwiftUI view.
class ShareViewController: UIViewController {

    // The ViewModel that will manage the state and logic of our translation process.
    private var viewModel: TranslationViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        // 1. Initialize the ViewModel with the extensionContext.
        // The extensionContext is the bridge to the host app (e.g., Photos),
        // providing access to the shared items.
        let viewModel = TranslationViewModel(extensionContext: self.extensionContext)
        self.viewModel = viewModel
        
        // 2. Create our main SwiftUI view, passing the ViewModel to it.
        let swiftUIView = TranslationView(viewModel: viewModel)

        // 3. Embed the SwiftUI view within a UIHostingController.
        // This is the standard way to bridge between UIKit and SwiftUI.
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // 4. Add the hosting controller as a child and its view to the view hierarchy.
        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        // 5. Set up Auto Layout constraints to make the SwiftUI view fill the entire screen.
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
        
        // Set a background color for the view controller's view.
        // This can be helpful for debugging the layout.
        self.view.backgroundColor = .systemBackground
    }
}
