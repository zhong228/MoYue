import SwiftUI
import UIKit

/// A document can arrive while any tab, sheet, or reader is visible. Attach to
/// this scene's actual window and present above its current controller, rather
/// than asking an already occupied root SwiftUI sheet to present another one.
struct ImportedBookPresentation: UIViewControllerRepresentable {
    let request: SharedImportQueueDrainer.ReaderRequest?
    let store: BookStore
    let subscriptionStore: SubscriptionStore
    let didPresent: (UUID) -> Void
    var customizationRequest: SharedCustomizationDocument? = nil
    var didPresentCustomization: (UUID) -> Void = { _ in }

    func makeUIViewController(context: Context) -> ImportedBookPresentationController {
        ImportedBookPresentationController()
    }

    func updateUIViewController(_ controller: ImportedBookPresentationController, context: Context) {
        controller.receive(requestID: customizationRequest?.id ?? request?.id, makeDestination: {
            if let customizationRequest {
                return UIHostingController(rootView:
                    SharedCustomizationImportView(document: customizationRequest)
                        .id(customizationRequest.id)
                )
            }
            guard let request else { return nil }
            return UIHostingController(rootView:
                BookReaderView(bookId: request.bookID)
                    .id(request.bookID)
                    .environmentObject(store)
                    .environmentObject(subscriptionStore)
                    .environment(\.appDependencies, .live)
            )
        }, didPresent: customizationRequest == nil ? didPresent : didPresentCustomization)
    }
}

@MainActor
final class ImportedBookPresentationController: UIViewController {
    private var pendingID: UUID?
    private var presentingID: UUID?
    private var makeDestination: (() -> UIViewController?)?
    private var didPresent: ((UUID) -> Void)?
    private var waitingForTransition = false
    private weak var presentationWindow: UIWindow?

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPending()
    }

    func receive(requestID: UUID?, makeDestination: @escaping () -> UIViewController?,
                 didPresent: @escaping (UUID) -> Void) {
        pendingID = requestID
        self.makeDestination = makeDestination
        self.didPresent = didPresent
        presentPending()
    }

    func presentPending() {
        // Full-screen readers remove the underlying scene view from the window.
        // Keep this scene's window while it is attached so subsequent Open In
        // events can still reach the controller currently presented above it.
        if let window = viewIfLoaded?.window { presentationWindow = window }
        guard !waitingForTransition, presentingID == nil,
              let requestID = pendingID,
              let window = presentationWindow, !window.isHidden,
              var presenter = window.rootViewController else { return }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        // Open In can arrive during a sheet's dismissal or scene activation.
        // Wait for UIKit's real transition completion, never a timed retry.
        if let transition = presenter.transitionCoordinator {
            waitingForTransition = true
            let scheduled = transition.animate(alongsideTransition: nil) { [weak self] _ in
                self?.waitingForTransition = false
                self?.presentPending()
            }
            if scheduled { return }
            waitingForTransition = false
        }
        guard let destination = makeDestination?() else { return }
        presentingID = requestID
        destination.modalPresentationStyle = .fullScreen
        let acknowledge = didPresent
        presenter.present(destination, animated: true) { [weak self] in
            guard let self else { return }
            self.presentingID = nil
            if self.pendingID == requestID { self.pendingID = nil }
            acknowledge?(requestID)
            self.presentPending()
        }
    }
}

#Preview {
    ImportedBookPresentation(request: nil, store: BookStore(),
                             subscriptionStore: .shared, didPresent: { _ in })
}
