import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case blue, purple, teal, red, orange, green
    var id: String { rawValue }

    static let storageKey = "appAccent"
    static var current: AppAccent {
        AppAccent(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .blue
    }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0, green: 0.341, blue: 1)
        case .purple: return Color(red: 0.49, green: 0.32, blue: 0.98)
        case .teal: return Color(red: 0, green: 0.6, blue: 0.62)
        case .red: return Color(red: 0.9, green: 0.16, blue: 0.27)
        case .orange: return Color(red: 0.96, green: 0.48, blue: 0.08)
        case .green: return Color(red: 0.12, green: 0.66, blue: 0.34)
        }
    }

    var title: String {
        switch self {
        case .blue: return t("Blue")
        case .purple: return t("Purple")
        case .teal: return t("Teal")
        case .red: return t("Red")
        case .orange: return t("Orange")
        case .green: return t("Green")
        }
    }
}

struct QuickAppearanceButton: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            appearance = colorScheme == .dark ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(t(colorScheme == .dark ? "Day mode" : "Night mode"))
        .accessibilityIdentifier("appearance.quickToggle")
    }
}

extension View {
    func quickAppearanceToggle() -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                QuickAppearanceButton()
            }
        }
    }
}
