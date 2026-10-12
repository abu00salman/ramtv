import SwiftUI

@main
struct RaMtvApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
                .environment(\.layoutDirection, (AppLanguage(rawValue: language) ?? .system).isArabic ? .rightToLeft : .leftToRight)
                .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .dark).colorScheme)
                .tint(Color.ram)
        }
    }
}
