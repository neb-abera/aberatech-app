import AberaCore
import SwiftUI

/// Who is signed in, Apple Health for Neb, and Sign out.
struct MeView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Signed in as", value: model.session?.name ?? "")
                        .accessibilityIdentifier("signed-in-as")
                }
                if model.isOwner {
                    Section {
                        Button("Send weigh-ins now") { Task { await model.sendWeights() } }
                            .disabled(model.busy)
                            .accessibilityIdentifier("send-weights")
                        if let status = model.weightStatus {
                            Text(status).font(.footnote).accessibilityIdentifier("weight-status")
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text(
                            "Lose It writes your weigh-ins to Apple Health. This phone sends the last 30 days to abera.tech/fitness each time the app opens and when a new one is added."
                        )
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                        .accessibilityIdentifier("sign-out")
                }
            }
            .navigationTitle("Me")
        }
    }
}
