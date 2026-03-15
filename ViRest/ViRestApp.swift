import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn
import UIKit

@main
struct ViRestApp: App {
    @StateObject private var container = AppContainer()

    init() {
        FirebaseApp.configure()

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: FirebaseApp.app()?.options.clientID ?? ""
        )

        Self.configureNavigationBarAppearance()
        Self.configureSegmentedControlAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
        .modelContainer(container.modelContainer)
    }

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Color.slateGray)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.slateGray)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func configureSegmentedControlAppearance() {
        let appearance = UISegmentedControl.appearance()
        appearance.backgroundColor = .clear
        appearance.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.14)

        appearance.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont(name: "AvenirNext-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        ], for: .normal)

        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.vibrantGreen),
            .font: UIFont(name: "AvenirNext-DemiBold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        appearance.setTitleTextAttributes(selectedAttributes, for: .selected)
        appearance.setTitleTextAttributes(selectedAttributes, for: .highlighted)
        appearance.setTitleTextAttributes(
            selectedAttributes,
            for: UIControl.State(rawValue: UIControl.State.selected.rawValue | UIControl.State.highlighted.rawValue)
        )
    }
}
