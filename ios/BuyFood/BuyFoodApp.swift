import SwiftUI

@main
struct BuyFoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.user != nil {
                ListsView()
            } else {
                SignInView()
            }
        }
        .task { await auth.refreshOnLaunch() }
        .task(id: auth.user?.id) {
            if let user = auth.user {
                LiveUpdates.shared.start()
                PushManager.shared.register(userID: user.id, authToken: APIClient.shared.token ?? "")
                PhoneLink.shared.send(token: APIClient.shared.token, userID: user.id)
            } else {
                LiveUpdates.shared.stop()
                PhoneLink.shared.send(token: nil, userID: nil)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, auth.user != nil { LiveUpdates.shared.start() }
        }
    }
}
