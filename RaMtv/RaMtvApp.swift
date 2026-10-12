import SwiftUI

@main
struct RaMtvApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
                .environment(\.layoutDirection, (AppLanguage(rawValue: language) ?? .system).isArabic ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark)
                .tint(Color.ram)
        }
    }
}
