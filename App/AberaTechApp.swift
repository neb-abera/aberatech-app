import AberaCore
import AuthenticationServices
import SwiftUI
import UIKit

@main
struct AberaTechApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        #if DEBUG
            // The UI tests run in -demo mode, faster with animations off.
            if ProcessInfo.processInfo.arguments.contains("-demo") { UIView.setAnimationsEnabled(false) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.start() }
        }
        .onChange(of: phase) { _, now in
            guard now == .active, model.started, model.session != nil else { return }
            Task { await model.refresh() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Here and not in a view: iOS launches the app in the background for
        // a new weigh-in, and HealthKit delivers it only to a query set up
        // before launch finishes.
        AppModel.observeWeights()
        return true
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        if !model.started {
            ProgressView()
        } else if model.session == nil {
            SignInView(model: model)
        } else {
            MainTabs(model: model)
        }
    }
}

struct SignInView: View {
    @Bindable var model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "house")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("aberaTech")
                .font(.largeTitle.bold())
            Text("Sign in with the Google account Neb added for you.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    await model.signIn { url in
                        try await webAuthenticationSession.authenticate(
                            using: url, callback: .customScheme(SignIn.scheme), additionalHeaderFields: [:])
                    }
                }
            } label: {
                Label("Sign in with Google", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.busy)
            .accessibilityIdentifier("sign-in")
            if let error = model.signInError {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("sign-in-error")
            }
            Spacer()
        }
        .padding(32)
    }
}

struct MainTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Tab("Requests", systemImage: "tray.full") { RequestsView(model: model) }
            Tab("Fitness", systemImage: "figure.run") { FitnessView(model: model) }
            Tab("Wish list", systemImage: "gift") { WishListView(model: model) }
            Tab("Me", systemImage: "person.crop.circle") { MeView(model: model) }
        }
    }
}
