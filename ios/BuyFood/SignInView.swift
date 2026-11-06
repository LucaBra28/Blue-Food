import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 132
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 50

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image("Cart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .accessibilityHidden(true)
                    Text("Willkommen bei BuyFood")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(symbol: "person.2.fill", title: "Gemeinsam einkaufen",
                               text: "Teile Listen mit Familie und Freunden.")
                    FeatureRow(symbol: "checklist", title: "Immer auf dem gleichen Stand",
                               text: "Artikel hinzufügen, abhaken und Mengen anpassen.")
                    FeatureRow(symbol: "barcode.viewfinder", title: "Barcode scannen",
                               text: "Artikel schnell per Kamera erfassen.")
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                SignInWithAppleButton(.signIn) { request in
                    auth.prepare(request)
                } onCompletion: { result in
                    Task { await auth.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: buttonHeight)
                .frame(maxWidth: 420)
                .disabled(auth.isWorking)
                .overlay { if auth.isWorking { ProgressView() } }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
