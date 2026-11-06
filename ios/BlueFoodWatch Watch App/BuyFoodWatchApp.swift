import SwiftUI

@main
struct BuyFoodWatchApp: App {
    init() {
        WatchLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
